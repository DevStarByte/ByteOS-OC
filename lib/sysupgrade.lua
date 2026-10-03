--[[
  /lib/sysupgrade.lua - upgrades the ByteOS base system ("byteos" package)
  straight from its GitHub repository. Used by `pacman -Syu`.

    local up = sysupgrade.check(repo, branch)  -> info | nil, reason
        up.uptodate, up.oldVersion, up.version, up.name
    sysupgrade.download(up, progress)          -> true | nil, reason
        stages and compiles every changed file; changes nothing on error
    sysupgrade.apply(up, progress)             -> true | nil, reason
        up.pacnew lists /etc files that were installed as <file>.new
    sysupgrade.discard()                       -- drop staged downloads
    sysupgrade.rollback()                      -> true if an upgrade was undone

  Safety:
    * Only OS files are replaced: /init.lua, /boot, /sbin, /lib, /bin,
      /etc/os-release and /etc/issue. /home, /var, user accounts and
      installed packages are never touched.
    * /etc files the user changed are kept; the new version is written next
      to them as <file>.new (like pacman's .pacnew).
    * Everything replaced is moved to /var/lib/pacman/byteos/backup first and
      a journal is written before the first file moves, so even an
      interrupted upgrade can be undone. If the upgraded system panics before
      the login prompt, /init.lua rolls back on its own.
]]--

local internet = require("internet")
local fs = kernel.fs

local sysupgrade = {}

local LIB      = "/var/lib/pacman/byteos"
local STATE    = LIB .. "/state"        -- installed commit + blob sha per file
local BACKUP   = LIB .. "/backup"       -- previous versions of replaced files
local JOURNAL  = LIB .. "/backup.list"  -- how to undo the last upgrade
local PENDING  = LIB .. "/pending"      -- set until the new system has booted
local PRISTINE = LIB .. "/pristine"     -- unmodified upstream copies of /etc files
local STAGE    = "/var/cache/pacman/byteos"
local LOCAL    = "var/lib/pacman/local"
-- placeholder entries from before the base system was one package
local LEGACY   = { "bytekernel", "coreutils", "pacman" }

-- Which repository paths belong to the running system.
--   "os"     : owned by ByteOS, replaced on upgrade
--   "config" : /etc files the user may edit, replaced only if untouched
--   nil      : not installed (README, docs, home/, var/ ...)
local OS_DIRS  = { "boot/", "sbin/", "lib/", "bin/" }
local OS_FILES = { ["init.lua"] = true, ["etc/os-release"] = true, ["etc/issue"] = true }
local NEVER    = { ["etc/passwd"] = true, ["etc/hostname"] = true }

-- Files older versions shipped that are gone now. Normally a file that
-- disappears upstream is removed because the state file lists it, but a
-- system installed by copying files has no state yet, so these are named
-- here. Removal is journaled like every other change (pacman --rollback).
local OBSOLETE = {
  -- OpenOS leftovers nothing in ByteOS loaded (removed in 1.3.1)
  "boot/00_base.lua", "boot/01_process.lua", "boot/02_os.lua", "boot/03_io.lua",
  "boot/04_component.lua", "boot/10_devfs.lua", "boot/89_rc.lua",
  "boot/90_filesystem.lua", "boot/91_gpu.lua", "boot/92_keyboard.lua",
  "boot/93_term.lua", "boot/94_shell.lua",
  "lib/tty.lua", "lib/note.lua", "lib/uuid.lua", "lib/transforms.lua",
  -- replaced by pacman -Syu and makepkg
  "bin/sysupdate.lua", "etc/sysupdate.conf", "bin/mkpkg.lua",
}

local function classify(path)
  if OS_FILES[path] then return "os" end
  if NEVER[path] then return nil end
  for _, d in ipairs(OS_DIRS) do
    if path:sub(1, #d) == d then return "os" end
  end
  if path:sub(1, 4) == "etc/" then return "config" end
  return nil
end

-- ---- Files -----------------------------------------------------------------
local function parent(p) return p:match("^(.*)/[^/]*$") or "" end
local function mkdirp(dir)
  if dir ~= "" and not fs.exists(dir) then fs.makeDirectory(dir) end
end
local function readIf(path)
  if fs.exists(path) then return fs.readAll(path) end
end
local function writeTo(path, data)
  mkdirp(parent(path))
  return fs.writeAll(path, data)
end

local function readState()
  local st = { files = {} }
  for line in (readIf(STATE) or ""):gmatch("[^\n]+") do
    local a, b = line:match("^(%S+) (.+)$")
    if a == "commit" then st.commit = b elseif a then st.files[b] = a end
  end
  return st
end

local function field(text, key)
  return (text or ""):match(key .. '="?([^"\r\n]+)')
end

-- ---- GitHub ----------------------------------------------------------------
local function fetch(url, accept)
  local data, e, code = internet.fetch(url, accept and { Accept = accept })
  if not data and (code == 403 or code == 429) then
    e = "GitHub rate limit reached (60 checks per hour), try again later"
  end
  return data, e
end

local function urlPath(p)
  return (p:gsub("[^%w%-%._~/]", function(c) return ("%%%02X"):format(c:byte()) end))
end

-- Pull { path, sha, size } for every file out of a git tree listing.
local function parseTree(json)
  local arr = json:match('"tree"%s*:%s*(%b[])')
  if not arr then return nil, "unexpected reply from GitHub" end
  local files = {}
  for obj in arr:gmatch("%b{}") do
    local path = obj:match('"path"%s*:%s*"(.-)"')
    local typ  = obj:match('"type"%s*:%s*"(.-)"')
    local sha  = obj:match('"sha"%s*:%s*"(%x+)"')
    local size = tonumber(obj:match('"size"%s*:%s*(%d+)'))
    if typ == "blob" and path and sha then
      files[#files + 1] = { path = path, sha = sha, size = size or 0 }
    end
  end
  return files
end

-- ---- Check -----------------------------------------------------------------
function sysupgrade.check(repo, branch)
  local api = "https://api.github.com/repos/" .. repo
  local raw = "https://raw.githubusercontent.com/" .. repo .. "/"
  local latest, e = fetch(api .. "/commits/" .. branch, "application/vnd.github.sha")
  if not latest then return nil, e end
  latest = latest:match("^%s*(%x+)%s*$")
  if not latest then return nil, "unexpected reply from GitHub" end

  local up = {
    repo = repo, api = api, raw = raw, commit = latest, short = latest:sub(1, 7),
    state = readState(),
  }
  local desc = readIf("/" .. LOCAL .. "/byteos/desc")
  up.oldVersion = desc and desc:match("version=(%S+)")
    or field(readIf("/etc/os-release"), "VERSION_ID") or "?"
  up.uptodate = up.state.commit == latest
  if up.uptodate then up.version = up.oldVersion; return up end

  local release = fetch(raw .. latest .. "/etc/os-release")
  up.name = field(release, "PRETTY_NAME") or "ByteOS"
  up.version = (field(release, "VERSION_ID") or "0") .. ".g" .. up.short
  return up
end

-- ---- Download into the staging area ----------------------------------------
function sysupgrade.discard()
  if fs.exists(STAGE) then fs.remove(STAGE) end
end

function sysupgrade.download(up, progress)
  local json, e = fetch(up.api .. "/git/trees/" .. up.commit .. "?recursive=1")
  if not json then return nil, "cannot list files: " .. e end
  local tree; tree, e = parseTree(json)
  json = nil
  if not tree then return nil, e end

  local managed, remote = {}, {}
  for _, f in ipairs(tree) do
    f.kind = classify(f.path)
    if f.kind then managed[#managed + 1] = f; remote[f.path] = f end
  end
  if not remote["init.lua"] or not remote["boot/kernel.lua"] then
    return nil, up.repo .. " does not look like ByteOS, refusing to install it"
  end

  local fetchList, total = {}, 0
  for _, f in ipairs(managed) do
    if up.state.files[f.path] ~= f.sha or not fs.exists("/" .. f.path) then
      fetchList[#fetchList + 1] = f
      total = total + f.size
    end
  end

  -- Space: the staged copy plus the backups of what it replaces.
  local root = fs.resolve("/")
  local free = (root.spaceTotal() or math.huge) - (root.spaceUsed() or 0)
  local need = total * 2 + 16384
  if need > free then
    return nil, ("not enough disk space: need %d KiB, have %d KiB")
      :format(math.ceil(need / 1024), math.floor(free / 1024))
  end

  sysupgrade.discard()
  mkdirp(STAGE)
  local function fail(msg) sysupgrade.discard(); return nil, msg end
  local got = 0
  for i, f in ipairs(fetchList) do
    local staged = STAGE .. "/" .. f.path
    mkdirp(parent(staged))
    local out = fs.open(staged, "w")
    if not out then return fail("cannot write " .. staged) end
    local size = 0
    local label = ("(%d/%d) %s"):format(i, #fetchList, f.path)
    progress(label, total > 0 and got / total or 0)
    local ok, why = internet.get(up.raw .. up.commit .. "/" .. urlPath(f.path), function(c)
      out:write(c)
      size = size + #c
    end)
    out:close()
    if not ok then return fail(f.path .. ": " .. why) end
    if size ~= f.size then
      return fail(("%s: got %d bytes, expected %d"):format(f.path, size, f.size))
    end
    if f.path:match("%.lua$") then
      local okLoad, perr = load(fs.readAll(staged), "=" .. f.path, "t", {})
      if not okLoad then return fail("new version is broken: " .. tostring(perr)) end
    end
    got = got + size
  end

  -- Work out what actually changes.
  -- op: "add", "replace", "delete" (gone upstream),
  --     "pacnew" (user-edited /etc file: new version goes to <file>.new)
  local ops, pristine = {}, {}
  for _, f in ipairs(fetchList) do
    local new = fs.readAll(STAGE .. "/" .. f.path)
    local cur = readIf("/" .. f.path)
    if f.kind == "config" then pristine[f.path] = new end
    if cur == new then
      -- already identical
    elseif cur == nil then
      ops[#ops + 1] = { op = "add", path = f.path }
    elseif f.kind == "os" or readIf(PRISTINE .. "/" .. f.path) == cur then
      ops[#ops + 1] = { op = "replace", path = f.path }
    else
      ops[#ops + 1] = { op = "pacnew", path = f.path }
    end
  end
  local gone = {}
  for path in pairs(up.state.files) do
    if not remote[path] and classify(path) == "os" then gone[path] = true end
  end
  for _, path in ipairs(OBSOLETE) do
    if not remote[path] then gone[path] = true end
  end
  for path in pairs(gone) do
    if fs.exists("/" .. path) then ops[#ops + 1] = { op = "delete", path = path } end
  end
  table.sort(ops, function(a, b) return a.path < b.path end)

  -- The bookkeeping goes through the same journal, so a rollback restores
  -- the old state file and package database entries too.
  -- `path` (a file or a whole directory) is moved into place as one unit.
  local function stageOp(path)
    ops[#ops + 1] = { op = fs.exists("/" .. path) and "replace" or "add", path = path }
  end
  local stateLines = { "commit " .. up.commit }
  local fileList = {}
  for _, f in ipairs(managed) do
    stateLines[#stateLines + 1] = f.sha .. " " .. f.path
    fileList[#fileList + 1] = "/" .. f.path
  end
  writeTo(STAGE .. STATE, table.concat(stateLines, "\n") .. "\n")
  stageOp(STATE:sub(2))
  local entry = LOCAL .. "/byteos"
  writeTo(STAGE .. "/" .. entry .. "/desc",
    "name=byteos\nversion=" .. up.version ..
    "\ndesc=ByteOS base system (kernel, init, shell and core tools)\nformat=git\n")
  writeTo(STAGE .. "/" .. entry .. "/files", table.concat(fileList, "\n") .. "\n")
  stageOp(entry)
  for _, name in ipairs(LEGACY) do
    if fs.exists("/" .. LOCAL .. "/" .. name) then
      ops[#ops + 1] = { op = "delete", path = LOCAL .. "/" .. name }
    end
  end

  up.ops, up.pristine, up.downloaded = ops, pristine, #fetchList
  return true
end

-- ---- Apply -----------------------------------------------------------------
-- Undo the last upgrade using the journal written before it was applied.
-- /init.lua carries a copy of this for when the new system cannot boot.
function sysupgrade.rollback()
  local list = readIf(JOURNAL)
  if not list then return false end
  for op, path in list:gmatch("(%S+) ([^\n]+)") do
    local here, saved = "/" .. path, BACKUP .. "/" .. path
    if op == "remove" then
      if fs.exists(here) then fs.remove(here) end
    elseif op == "restore" and fs.exists(saved) then
      if fs.exists(here) then fs.remove(here) end
      mkdirp(parent(here))
      fs.rename(saved, here)
    end
  end
  fs.remove(JOURNAL); fs.remove(PENDING); fs.remove(BACKUP)
  return true
end

function sysupgrade.canRollback() return fs.exists(JOURNAL) end

function sysupgrade.apply(up, progress)
  local ops = up.ops
  if fs.exists(BACKUP) then fs.remove(BACKUP) end
  mkdirp(BACKUP)
  local journal = {}
  for _, o in ipairs(ops) do
    if o.op == "replace" or o.op == "delete" then
      journal[#journal + 1] = "restore " .. o.path
    elseif o.op == "add" then
      journal[#journal + 1] = "remove " .. o.path
    else
      journal[#journal + 1] = "remove " .. o.path .. ".new"
    end
  end
  fs.writeAll(JOURNAL, table.concat(journal, "\n") .. "\n")
  fs.writeAll(PENDING, up.commit .. "\n")

  up.pacnew = {}
  for i, o in ipairs(ops) do
    progress(o.path, (i - 1) / #ops)
    local staged, dest = STAGE .. "/" .. o.path, "/" .. o.path
    local ok = true
    if o.op == "replace" or o.op == "delete" then
      local saved = BACKUP .. "/" .. o.path
      mkdirp(parent(saved))
      ok = fs.rename(dest, saved)
    end
    if ok and o.op == "pacnew" then
      dest = dest .. ".new"
      if fs.exists(dest) then fs.remove(dest) end
      up.pacnew[#up.pacnew + 1] = "/" .. o.path
    end
    if ok and o.op ~= "delete" then
      mkdirp(parent(dest))
      ok = fs.rename(staged, dest)
    end
    if not ok then
      sysupgrade.rollback()
      sysupgrade.discard()
      return nil, "could not install /" .. o.path .. ", the previous system was restored"
    end
  end
  progress("byteos", 1)

  for path, content in pairs(up.pristine) do writeTo(PRISTINE .. "/" .. path, content) end
  sysupgrade.discard()
  return true
end

return sysupgrade
