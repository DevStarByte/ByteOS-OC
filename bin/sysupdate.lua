--[[
  sysupdate - update ByteOS itself from GitHub through the internet card

    sysupdate              check for a newer ByteOS and install it
    sysupdate -c           only check, change nothing
    sysupdate -y           do not ask for confirmation
    sysupdate -f           re-check every file, even if already up to date
    sysupdate --rollback   undo the last update

  Safe by design:
    * Every file is downloaded into /var/cache/sysupdate/stage first and
      every .lua file is compiled. The system is only touched once all of
      that succeeded; a failed download changes nothing.
    * Only OS files are replaced: /init.lua, /boot, /sbin, /lib, /bin,
      /etc/os-release and /etc/issue. /home, /var, user accounts and
      installed packages are never touched.
    * Other files in /etc that you changed are kept; the new upstream
      version is written next to them as <file>.new (like pacman's .pacnew).
    * Every replaced file is moved to /var/lib/sysupdate/backup first, so
      `sysupdate --rollback` restores the previous system. If the updated
      system panics before it reaches the login prompt, /init.lua rolls the
      update back on its own.

  Settings live in /etc/sysupdate.conf (REPO=owner/name, BRANCH=master).
]]--

local fs   = k.fs
local args = arg or {}
local T    = term.theme
local W    = term.size()

local CONF     = "/etc/sysupdate.conf"
local LIB      = "/var/lib/sysupdate"
local STATE    = LIB .. "/state"         -- installed commit + blob sha per file
local BACKUP   = LIB .. "/backup"        -- previous versions of replaced files
local JOURNAL  = LIB .. "/backup.list"   -- how to undo the last update
local PENDING  = LIB .. "/pending"       -- set until the new system has booted
local PRISTINE = LIB .. "/pristine"      -- unmodified upstream copies of /etc files
local STAGE    = "/var/cache/sysupdate/stage"

-- Which repository paths belong to the running system.
--   "os"     : owned by ByteOS, replaced on update
--   "config" : /etc files the user may edit, replaced only if untouched
--   nil      : not installed (README, docs, repo/, home/, var/ ...)
local OS_DIRS  = { "boot/", "sbin/", "lib/", "bin/" }
local OS_FILES = { ["init.lua"] = true, ["etc/os-release"] = true, ["etc/issue"] = true }
local NEVER    = { ["etc/passwd"] = true, ["etc/hostname"] = true }

local function classify(path)
  if OS_FILES[path] then return "os" end
  if NEVER[path] then return nil end
  for _, d in ipairs(OS_DIRS) do
    if path:sub(1, #d) == d then return "os" end
  end
  if path:sub(1, 4) == "etc/" then return "config" end
  return nil
end

-- ---- Output ----------------------------------------------------------------
local function header(msg)
  term.cwrite(T.accent, ":: ")
  term.cwrite(T.bright, msg .. "\n")
end
local function info(msg) term.cwrite(T.fg, msg .. "\n") end
local function warn(msg)
  term.cwrite(T.warn, "warning: ")
  term.cwrite(T.fg, msg .. "\n")
end
local function err(msg)
  term.cwrite(T.err, "error: ")
  term.cwrite(T.fg, msg .. "\n")
end

local NOCONFIRM = false
local function confirm(question)
  term.cwrite(T.accent, ":: ")
  term.cwrite(T.bright, question .. " [Y/n] ")
  if NOCONFIRM then term.write("\n"); return true end
  local a = (term.read() or "n"):lower()
  return a == "" or a == "y" or a == "yes"
end

-- A full-width progress line: " label            [#########-----] 100%"
local function progress(label, frac)
  local barW = math.max(10, math.min(30, W - 30))
  local labelW = W - barW - 9
  local _, y = term.getCursor()
  term.setCursor(1, y)
  term.cwrite(T.fg, term.pad(term.usub(" " .. label, 1, labelW), labelW))
  local filled = math.floor(barW * frac + 0.5)
  term.cwrite(T.muted, " [")
  term.cwrite(T.accent, string.rep("#", filled))
  term.cwrite(T.dim, string.rep("-", barW - filled))
  term.cwrite(T.muted, "]")
  term.cwrite(T.fg, ("%4d%%"):format(math.floor(frac * 100 + 0.5)))
end

-- ---- Files -----------------------------------------------------------------
local function parent(p) return p:match("^(.*)/[^/]*$") or "" end
local function mkdirp(dir)
  if dir ~= "" and not fs.exists(dir) then fs.makeDirectory(dir) end
end
local function readIf(path)
  if fs.exists(path) then return fs.readAll(path) end
end

local function readConf()
  local c = { REPO = "DevStarByte/ByteOS-OC", BRANCH = "master" }
  for line in (readIf(CONF) or ""):gmatch("[^\n]+") do
    local key, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key then c[key] = v end
  end
  return c
end

local function readState()
  local st = { files = {} }
  for line in (readIf(STATE) or ""):gmatch("[^\n]+") do
    local a, b = line:match("^(%S+) (.+)$")
    if a == "commit" then st.commit = b elseif a then st.files[b] = a end
  end
  return st
end

local function writeState(commit, files)
  local out = { "commit " .. commit }
  for _, f in ipairs(files) do out[#out + 1] = f.sha .. " " .. f.path end
  mkdirp(LIB)
  fs.writeAll(STATE, table.concat(out, "\n") .. "\n")
end

local function osName(release)
  return (release or ""):match('PRETTY_NAME="?([^"\n]+)') or "ByteOS"
end

-- Undo the last update using the journal written before it was applied.
-- /init.lua carries a copy of this for when the new system cannot boot.
local function rollback()
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

-- ---- HTTP ------------------------------------------------------------------
local inet

-- GET `url`, handing the body to sink(chunk) as it arrives.
local function get(url, sink, accept)
  local ok, h, reason = pcall(inet.request, url, nil,
    { ["User-Agent"] = "ByteOS-sysupdate", ["Accept"] = accept or "*/*" })
  if not ok or not h then return nil, tostring(ok and reason or h) end

  local deadline = computer.uptime() + 20
  while true do
    local okc, done, why = pcall(h.finishConnect)
    if not okc or done == nil then h.close(); return nil, tostring(okc and why or done) end
    if done then break end
    if computer.uptime() > deadline then h.close(); return nil, "connection timed out" end
    k.event.pull(0.05)
  end

  local code, message
  repeat
    code, message = h.response()
    if not code then
      if computer.uptime() > deadline then h.close(); return nil, "no response" end
      k.event.pull(0.05)
    end
  until code
  if code ~= 200 then
    h.close()
    if code == 403 or code == 429 then
      return nil, "GitHub rate limit reached (60 checks per hour), try again later"
    end
    return nil, ("HTTP %d %s"):format(code, message or "")
  end

  local idle = computer.uptime()
  while true do
    local okr, chunk, rerr = pcall(h.read, 8192)
    if not okr then h.close(); return nil, tostring(chunk) end
    if chunk == nil then
      h.close()
      if rerr then return nil, tostring(rerr) end
      return true
    end
    if #chunk > 0 then
      sink(chunk)
      idle = computer.uptime()
    elseif computer.uptime() - idle > 20 then
      h.close(); return nil, "download stalled"
    else
      k.event.pull(0.05)
    end
  end
end

local function getString(url, accept)
  local parts = {}
  local ok, e = get(url, function(c) parts[#parts + 1] = c end, accept)
  if not ok then return nil, e end
  return table.concat(parts)
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

-- ---- Main ------------------------------------------------------------------
local function usage()
  term.cwrite(T.bright, "usage: ")
  term.write("sysupdate [-c] [-y] [-f] [--rollback]\n")
  term.cwrite(T.muted, "  -c          only check for a new version\n")
  term.cwrite(T.muted, "  -y          do not ask for confirmation (and do not reboot)\n")
  term.cwrite(T.muted, "  -f          re-check every file\n")
  term.cwrite(T.muted, "  --rollback  restore the system from before the last update\n")
end

local CHECK, FORCE = false, false
for _, a in ipairs(args) do
  if a == "-c" or a == "--check" then CHECK = true
  elseif a == "-y" or a == "--noconfirm" then NOCONFIRM = true
  elseif a == "-f" or a == "--force" then FORCE = true
  elseif a == "--rollback" then
    if not fs.exists(JOURNAL) then err("there is no update to roll back"); return 1 end
    if not confirm("Restore the system from before the last update?") then return 1 end
    rollback()
    info("Previous system restored. Reboot to use it.")
    return 0
  elseif a == "-h" or a == "--help" then usage(); return 0
  else err("invalid option '" .. a .. "'"); usage(); return 1 end
end

local addr = component.list("internet")()
if not addr then
  err("no internet card installed")
  return 1
end
inet = component.proxy(addr)

local conf  = readConf()
local state = readState()
local api   = "https://api.github.com/repos/" .. conf.REPO
local raw   = "https://raw.githubusercontent.com/" .. conf.REPO .. "/"

header("Checking " .. conf.REPO .. " (" .. conf.BRANCH .. ")...")
local latest, e = getString(api .. "/commits/" .. conf.BRANCH, "application/vnd.github.sha")
if not latest then err("cannot reach GitHub: " .. e); return 1 end
latest = latest:match("^%s*(%x+)%s*$")
if not latest then err("unexpected reply from GitHub"); return 1 end

local here = osName(readIf("/etc/os-release"))
local short = latest:sub(1, 7)
local was = state.commit and state.commit:sub(1, 7) or "unknown build"

if state.commit == latest and not FORCE then
  info(here .. " (" .. short .. ") is up to date.")
  return 0
end

local newRelease = getString(raw .. latest .. "/etc/os-release")
local there = osName(newRelease)
info(("  installed  %s (%s)"):format(here, was))
term.cwrite(T.fg, "  available  ")
term.cwrite(T.green, ("%s (%s)\n"):format(there, short))
if CHECK then
  term.cwrite(T.muted, "Run "); term.cwrite(T.blue, "sysupdate")
  term.cwrite(T.muted, " to install it.\n")
  return 0
end

-- What does the new version consist of?
local json; json, e = getString(api .. "/git/trees/" .. latest .. "?recursive=1")
if not json then err("cannot list files: " .. e); return 1 end
local tree; tree, e = parseTree(json)
json = nil
if not tree then err(e); return 1 end

local managed, remote = {}, {}
for _, f in ipairs(tree) do
  f.kind = classify(f.path)
  if f.kind then managed[#managed + 1] = f; remote[f.path] = f end
end
if #managed == 0 or not remote["init.lua"] or not remote["boot/kernel.lua"] then
  err(conf.REPO .. " does not look like ByteOS, refusing to install it")
  return 1
end

local fetch, total = {}, 0
for _, f in ipairs(managed) do
  if FORCE or state.files[f.path] ~= f.sha or not fs.exists("/" .. f.path) then
    fetch[#fetch + 1] = f
    total = total + f.size
  end
end

-- Space: the staged copy plus the backups of what it replaces.
local root = fs.resolve("/")
local free = (root.spaceTotal() or math.huge) - (root.spaceUsed() or 0)
if total * 2 + 16384 > free then
  err(("not enough disk space: need %d KiB, have %d KiB")
    :format(math.ceil((total * 2 + 16384) / 1024), math.floor(free / 1024)))
  return 1
end

-- ---- Download into the staging area ----------------------------------------
local function abort(msg)
  term.write("\n")
  err(msg)
  if fs.exists(STAGE) then fs.remove(STAGE) end
  info("Nothing was changed.")
  return 1
end

if fs.exists(STAGE) then fs.remove(STAGE) end
mkdirp(STAGE)
header(("Downloading %d file%s (%d KiB)..."):format(#fetch, #fetch == 1 and "" or "s",
  math.ceil(total / 1024)))
local got = 0
for i, f in ipairs(fetch) do
  local staged = STAGE .. "/" .. f.path
  mkdirp(parent(staged))
  local out = fs.open(staged, "w")
  if not out then return abort("cannot write " .. staged) end
  local size = 0
  local label = ("(%d/%d) %s"):format(i, #fetch, f.path)
  progress(label, total > 0 and got / total or 0)
  local ok, why = get(raw .. latest .. "/" .. urlPath(f.path), function(c)
    out:write(c)
    size = size + #c
  end)
  out:close()
  if not ok then return abort(f.path .. ": " .. why) end
  if size ~= f.size then
    return abort(("%s: got %d bytes, expected %d"):format(f.path, size, f.size))
  end
  if f.path:match("%.lua$") then
    local okLoad, perr = load(fs.readAll(staged), "=" .. f.path, "t", {})
    if not okLoad then return abort("new version is broken: " .. tostring(perr)) end
  end
  got = got + size
  progress(label, total > 0 and got / total or 1)
end
progress(("downloaded %d file%s"):format(#fetch, #fetch == 1 and "" or "s"), 1)
term.write("\n")

-- ---- Work out what actually changes ----------------------------------------
-- op: "add" (new file), "replace", "delete" (gone upstream),
--     "pacnew" (user-edited /etc file: new version goes to <file>.new)
local ops, pristine = {}, {}
for _, f in ipairs(fetch) do
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
-- OS files from the installed version that no longer exist upstream
for path in pairs(state.files) do
  if not remote[path] and classify(path) == "os" and fs.exists("/" .. path) then
    ops[#ops + 1] = { op = "delete", path = path }
  end
end
table.sort(ops, function(a, b) return a.path < b.path end)

local function finish()
  writeState(latest, managed)
  for path, content in pairs(pristine) do
    mkdirp(parent(PRISTINE .. "/" .. path))
    fs.writeAll(PRISTINE .. "/" .. path, content)
  end
  if fs.exists(STAGE) then fs.remove(STAGE) end
end

if #ops == 0 then
  finish()
  info("All files already match " .. short .. "; nothing to install.")
  return 0
end

local MARK = {
  add     = { "+", T.green },
  replace = { "~", T.yellow },
  delete  = { "-", T.red },
  pacnew  = { "!", T.magenta },
}
header(("Changes (%d):"):format(#ops))
for _, o in ipairs(ops) do
  term.cwrite(MARK[o.op][2], "  " .. MARK[o.op][1] .. " ")
  term.cwrite(T.fg, "/" .. o.path)
  if o.op == "pacnew" then term.cwrite(T.muted, "  (yours kept, new one saved as .new)") end
  term.write("\n")
end
term.write("\n")
if not confirm("Install " .. there .. " (" .. short .. ")?") then
  if fs.exists(STAGE) then fs.remove(STAGE) end
  return 1
end

-- ---- Apply -----------------------------------------------------------------
-- The journal is written before anything is moved, so even an update that
-- is interrupted half-way can be rolled back.
header("Installing...")
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
local statePath = STATE:sub(2)
journal[#journal + 1] = (fs.exists(STATE) and "restore " or "remove ") .. statePath
fs.writeAll(JOURNAL, table.concat(journal, "\n") .. "\n")
fs.writeAll(PENDING, latest .. "\n")

local function moveAway(path)
  local saved = BACKUP .. "/" .. path
  mkdirp(parent(saved))
  return fs.rename("/" .. path, saved)
end

local failed
for i, o in ipairs(ops) do
  progress(o.path, (i - 1) / #ops)
  local staged, dest = STAGE .. "/" .. o.path, "/" .. o.path
  local ok = true
  if o.op == "replace" or o.op == "delete" then ok = moveAway(o.path) end
  if ok and o.op == "pacnew" then
    dest = dest .. ".new"
    if fs.exists(dest) then fs.remove(dest) end
  end
  if ok and o.op ~= "delete" then
    mkdirp(parent(dest))
    ok = fs.rename(staged, dest)
  end
  if not ok then failed = o.path; break end
end
if not failed and fs.exists(STATE) and not moveAway(statePath) then failed = statePath end

if failed then
  term.write("\n")
  err("could not install /" .. failed .. ", restoring the previous system")
  rollback()
  if fs.exists(STAGE) then fs.remove(STAGE) end
  return 1
end
progress(("installed %d change%s"):format(#ops, #ops == 1 and "" or "s"), 1)
term.write("\n")
finish()

term.write("\n")
term.cwrite(T.ok, "✓ ")
term.cwrite(T.bright, there .. " (" .. short .. ") installed.\n")
for _, o in ipairs(ops) do
  if o.op == "pacnew" then
    warn("/" .. o.path .. " was kept; compare it with /" .. o.path .. ".new")
  end
end
term.cwrite(T.muted, "Undo with ")
term.cwrite(T.blue, "sysupdate --rollback")
term.cwrite(T.muted, "; a failed boot is undone automatically.\n")
if NOCONFIRM then
  term.cwrite(T.muted, "Reboot to start the new version.\n")
elseif confirm("Reboot now to start the new version?") then
  computer.shutdown(true)
end
return 0
