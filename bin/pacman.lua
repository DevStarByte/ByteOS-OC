--[[
  pacman - ByteOS package manager (Arch-style CLI)

  Operations:
    pacman -S <pkg>...    install package(s) from configured repos
    pacman -R <pkg>...    remove installed package(s)
    pacman -Q             list installed packages
    pacman -Qi <pkg>      show info about installed package
    pacman -Sy            sync repository databases
    pacman -Syu           sync + upgrade everything
    pacman -Ss <regex>    search repos

  Repo layout (very simple):
    A repo is a directory containing:
      repo.db          : "name version description url\n" per line
      <name>-<ver>.pkg : a Lua table:
          return {
            files = { ["/path"] = "raw contents" },
            post_install = function() ... end,   -- optional
          }
      <name>-<ver>.pkg.z : same, but with `format = "lzw1"` and each file
        value is a base64-encoded LZW stream produced by lib/compress.lua.
        The compressed form is preferred when both exist.

  Local DB:
    /var/lib/pacman/local/<name>/desc      version + meta
    /var/lib/pacman/local/<name>/files     newline-separated installed paths
]]--

local fs       = k.fs
local args     = arg or {}
local compress = require("compress")

local CONF_PATH = "/etc/pacman.conf"
local LOCAL_DIR = "/var/lib/pacman/local"
local SYNC_DIR  = "/var/lib/pacman/sync"

local function ensureDirs()
  for _, d in ipairs({ "/var", "/var/lib", "/var/lib/pacman", LOCAL_DIR, SYNC_DIR }) do
    if not fs.exists(d) then fs.makeDirectory(d) end
  end
end

local function readRepos()
  local repos = {}
  if not fs.exists(CONF_PATH) then return repos end
  local section
  for raw in (fs.readAll(CONF_PATH) or ""):gmatch("[^\n]+") do
    local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if line:sub(1,1) == "#" or line == "" then
      -- comment/blank
    elseif line:sub(1,1) == "[" then
      section = line:match("%[(.-)%]")
      repos[section] = repos[section] or {}
    elseif section then
      local k_, v = line:match("^([^=]-)%s*=%s*(.+)$")
      if k_ then repos[section][k_] = v end
    end
  end
  return repos
end

local T = term.theme
local W = term.size()

-- pacman-style message helpers
local function header(msg)          -- ":: Synchronizing package databases..."
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

-- A full-width progress line: " label            [#########-----] 100%"
local function progress(label, frac)
  local barW = math.max(10, math.min(30, W - 30))
  local labelW = W - barW - 9
  local _, y = term.getCursor()
  term.setCursor(1, y)
  term.cwrite(T.fg, term.pad(" " .. label, labelW))
  local filled = math.floor(barW * frac + 0.5)
  term.cwrite(T.muted, " [")
  term.cwrite(T.accent, string.rep("#", filled))
  term.cwrite(T.dim, string.rep("-", barW - filled))
  term.cwrite(T.muted, "]")
  term.cwrite(T.fg, ("%4d%%"):format(math.floor(frac * 100 + 0.5)))
end

local NOCONFIRM = false
local function confirm(question)
  term.cwrite(T.accent, ":: ")
  term.cwrite(T.bright, question .. " [Y/n] ")
  if NOCONFIRM then term.write("\n"); return true end
  local a = (term.read() or "n"):lower()
  return a == "" or a == "y" or a == "yes"
end

-- Very small "downloader". A repo "Server" is either an http(s):// URL
-- (fetched through the internet card) or a path on a mounted disk
-- (e.g. /mnt/<id>/repo/core), which works without internet.
local function fetch(server, name)
  local p = server .. "/" .. name
  if p:match("^https?://") then
    local internet = require("internet")
    if not internet.available() then return nil, "no internet card for " .. p end
    local data, e = internet.fetch(p)
    if not data then return nil, e .. " " .. p end
    return data
  end
  if fs.exists(p) then return fs.readAll(p) end
  return nil, "not found: " .. p
end

local function syncRepo(rname, rconf)
  local data, e = fetch(rconf.Server, "repo.db")
  if not data then
    err("failed to synchronize " .. rname .. ": " .. tostring(e))
    return false
  end
  fs.makeDirectory(SYNC_DIR .. "/" .. rname)
  local old = fs.readAll(SYNC_DIR .. "/" .. rname .. "/repo.db")
  if old == data then
    term.cwrite(T.fg, " " .. rname)
    term.cwrite(T.muted, " is up to date\n")
  else
    fs.writeAll(SYNC_DIR .. "/" .. rname .. "/repo.db", data)
    progress(rname, 1); term.write("\n")
  end
  return true
end

local function findInRepos(pkg)
  for _, fname in ipairs(fs.list(SYNC_DIR) or {}) do
    local rname = fname:gsub("/$", "")
    local dbp   = SYNC_DIR .. "/" .. rname .. "/repo.db"
    if fs.exists(dbp) then
      for line in (fs.readAll(dbp) or ""):gmatch("[^\n]+") do
        local n, v, d = line:match("(%S+)%s+(%S+)%s+(.+)")
        if n == pkg then
          local repos = readRepos()
          return { name = n, version = v, desc = d, repo = rname, server = repos[rname] and repos[rname].Server }
        end
      end
    end
  end
end

local function isInstalled(pkg) return fs.isDirectory(LOCAL_DIR .. "/" .. pkg) end

local function installedVersion(pkg)
  local d = fs.readAll(LOCAL_DIR .. "/" .. pkg .. "/desc") or ""
  return d:match("version=(%S+)")
end

-- Install one package. `meta` comes from findInRepos(); idx/total drive the
-- "(1/3) installing foo" progress line.
local function installPackage(pkg, meta, idx, total)
  local label = ("(%d/%d) installing %s"):format(idx, total, pkg)
  local function fail(msg) term.write("\n"); err(msg); return false end
  progress(label, 0)

  -- Prefer the compressed package (.pkg.z), fall back to the plain .pkg.
  local stem = pkg .. "-" .. meta.version
  local data, e = fetch(meta.server, stem .. ".pkg.z")
  local compressed = data ~= nil
  if not data then
    data, e = fetch(meta.server, stem .. ".pkg")
  end
  if not data then return fail("download failed: " .. tostring(e)) end
  progress(label, 0.3)

  -- packages are Lua tables: return { files = {...}, post_install = function() ... end }
  local fn, perr = load(data, "=" .. pkg, "t", { string = string, table = table, math = math })
  if not fn then return fail("malformed package: " .. perr) end
  local ok, pkgtab = pcall(fn)
  if not ok or type(pkgtab) ~= "table" then return fail("invalid package payload") end

  -- Decompress file contents if the package declares a known format.
  if pkgtab.format == "lzw1" then
    for path, content in pairs(pkgtab.files or {}) do
      local plain, derr = compress.decode(content)
      if not plain then return fail("decompress failed for " .. path .. ": " .. tostring(derr)) end
      pkgtab.files[path] = plain
    end
  elseif pkgtab.format and pkgtab.format ~= "raw" then
    return fail("unknown package format: " .. tostring(pkgtab.format))
  end
  progress(label, 0.6)

  local installed = {}
  for path, content in pairs(pkgtab.files or {}) do
    local dir = path:match("(.+)/[^/]+$")
    if dir and not fs.exists(dir) then fs.makeDirectory(dir) end
    fs.writeAll(path, content)
    installed[#installed+1] = path
  end

  fs.makeDirectory(LOCAL_DIR .. "/" .. pkg)
  fs.writeAll(LOCAL_DIR .. "/" .. pkg .. "/desc",
              "name=" .. pkg .. "\nversion=" .. meta.version ..
              "\ndesc=" .. meta.desc ..
              "\nformat=" .. (pkgtab.format or "raw") .. "\n")
  fs.writeAll(LOCAL_DIR .. "/" .. pkg .. "/files", table.concat(installed, "\n") .. "\n")

  progress(label, 1); term.write("\n")
  if pkgtab.post_install then pcall(pkgtab.post_install) end
  return true
end

local function removePackage(pkg, idx, total)
  local label = ("(%d/%d) removing %s"):format(idx, total, pkg)
  progress(label, 0)
  local files = fs.readAll(LOCAL_DIR .. "/" .. pkg .. "/files") or ""
  for f in files:gmatch("[^\n]+") do if fs.exists(f) then fs.remove(f) end end
  for _, e_ in ipairs(fs.list(LOCAL_DIR .. "/" .. pkg) or {}) do
    fs.remove(LOCAL_DIR .. "/" .. pkg .. "/" .. e_)
  end
  fs.remove(LOCAL_DIR .. "/" .. pkg)
  progress(label, 1); term.write("\n")
  return true
end

local function queryAll()
  for _, e_ in ipairs(fs.list(LOCAL_DIR) or {}) do
    local n   = e_:gsub("/$", "")
    local d   = fs.readAll(LOCAL_DIR .. "/" .. n .. "/desc") or ""
    local ver = d:match("version=(%S+)") or "?"
    term.cwrite(T.bright, n .. " ")
    term.cwrite(T.green, ver .. "\n")
  end
end

local function queryInfo(pkg)
  if not pkg then err("no targets specified"); return end
  if not isInstalled(pkg) then err("package '" .. pkg .. "' was not found"); return end
  local d = fs.readAll(LOCAL_DIR .. "/" .. pkg .. "/desc") or ""
  local fields = {}
  for key, v in d:gmatch("(%w+)=([^\n]*)") do fields[key] = v end
  local files = {}
  for f in (fs.readAll(LOCAL_DIR .. "/" .. pkg .. "/files") or ""):gmatch("[^\n]+") do files[#files + 1] = f end
  local function row(label, value)
    term.cwrite(T.bright, term.pad(label, 14))
    term.cwrite(T.muted, ": ")
    term.cwrite(T.fg, (value or "None") .. "\n")
  end
  row("Name", fields.name or pkg)
  row("Version", fields.version)
  row("Description", fields.desc)
  row("Format", fields.format or "raw")
  row("Files", tostring(#files))
  for _, f in ipairs(files) do term.cwrite(T.muted, string.rep(" ", 16) .. f .. "\n") end
end

local function search(pat)
  for _, fname in ipairs(fs.list(SYNC_DIR) or {}) do
    local rname = fname:gsub("/$", "")
    local dbp   = SYNC_DIR .. "/" .. rname .. "/repo.db"
    if fs.exists(dbp) then
      for line in (fs.readAll(dbp) or ""):gmatch("[^\n]+") do
        local n, v, d = line:match("(%S+)%s+(%S+)%s+(.+)")
        if n and (not pat or n:find(pat) or (d or ""):find(pat)) then
          term.cwrite(T.magenta, rname .. "/")
          term.cwrite(T.bright, n .. " ")
          term.cwrite(T.green, v)
          if isInstalled(n) then term.cwrite(T.cyan, " [installed]") end
          term.write("\n")
          term.cwrite(T.fg, "    " .. (d or "") .. "\n")
        end
      end
    end
  end
end

-- ===== argument dispatch =====
local function usage()
  term.cwrite(T.bright, "usage: ")
  term.write("pacman <operation> [...]\n")
  term.cwrite(T.bright, "operations:\n")
  local ops = {
    { "-S <pkg>...", "install packages" },
    { "-R <pkg>...", "remove packages" },
    { "-Q",          "list installed packages" },
    { "-Qi <pkg>",   "show package information" },
    { "-Ss [regex]", "search the repositories" },
    { "-Sy",         "synchronize package databases" },
    { "-Syu",        "upgrade packages and the byteos base system" },
    { "--rollback",  "undo the last byteos upgrade" },
  }
  for _, o in ipairs(ops) do
    term.cwrite(T.green, "    " .. term.pad(o[1], 14))
    term.cwrite(T.fg, o[2] .. "\n")
  end
  term.cwrite(T.muted, "options: --noconfirm  do not ask for confirmation\n")
end

local function sync()
  header("Synchronizing package databases...")
  local repos, names = readRepos(), {}
  for name, conf in pairs(repos) do if conf.Server then names[#names + 1] = name end end
  table.sort(names)
  local ok = #names > 0
  for _, name in ipairs(names) do ok = syncRepo(name, repos[name]) and ok end
  if not ok then
    -- the usual cause: an old pacman.conf that -Syu kept next to a new one
    if fs.exists(CONF_PATH .. ".new") then
      warn("a newer config was saved as " .. CONF_PATH .. ".new; to use it run")
      term.cwrite(T.blue, "    mv " .. CONF_PATH .. ".new " .. CONF_PATH .. "\n")
    else
      warn("check the Server lines in " .. CONF_PATH)
    end
  end
  return ok
end

-- True once every configured repo has a synced database.
local function synced()
  for name, conf in pairs(readRepos()) do
    if conf.Server and not fs.exists(SYNC_DIR .. "/" .. name .. "/repo.db") then return false end
  end
  return true
end

-- Look every target up in the synced databases. Returns the list of
-- package metadata, or nil after printing why a target is missing.
local function resolve(targets)
  if not synced() then sync() end
  local list = {}
  for _, pkg in ipairs(targets) do
    local meta = findInRepos(pkg)
    if not meta then
      err("target not found: " .. pkg)
      if not synced() then
        term.cwrite(T.muted, "  the package databases could not be synchronized (see above)\n")
      else
        term.cwrite(T.muted, "  try ")
        term.cwrite(T.blue, "pacman -Sy")
        term.cwrite(T.muted, " to refresh, or ")
        term.cwrite(T.blue, "pacman -Ss " .. pkg)
        term.cwrite(T.muted, " to search\n")
      end
      return nil
    end
    if isInstalled(pkg) and installedVersion(pkg) == meta.version then
      warn(pkg .. "-" .. meta.version .. " is up to date -- reinstalling")
    end
    list[#list + 1] = meta
  end
  return list
end

-- "Packages (2) foo-1.0  bar-2.0" followed by the confirmation prompt.
local function confirmPackages(names, question)
  term.write("\n")
  term.cwrite(T.bright, ("Packages (%d) "):format(#names))
  term.cwrite(T.fg, table.concat(names, "  ") .. "\n\n")
  return confirm(question)
end

local function installAll(list)
  header("Processing package changes...")
  local ok = true
  for i, m in ipairs(list) do ok = installPackage(m.name, m, i, #list) and ok end
  return ok
end

local function install(targets)
  if #targets == 0 then err("no targets specified (use -h for help)"); return 1 end
  local list = resolve(targets)
  if not list then return 1 end
  info("resolving dependencies...")
  info("looking for conflicting packages...")
  local names = {}
  for _, m in ipairs(list) do names[#names + 1] = m.name .. "-" .. m.version end
  if not confirmPackages(names, "Proceed with installation?") then return 1 end
  return installAll(list) and 0 or 1
end

-- ---- Base system -----------------------------------------------------------
-- The OS itself is the "byteos" package. It is not in a repo.db: pacman
-- upgrades it file by file from the git repository named in pacman.conf.
local function baseRepo()
  local o = readRepos().options or {}
  return o.BaseRepo or "DevStarByte/ByteOS-OC", o.BaseBranch or "master"
end

-- Returns the pending base upgrade, or nil if there is none / it cannot
-- be checked right now (the reason is printed).
local function checkBase()
  if not require("internet").available() then
    info(" no internet card: skipping the byteos base system")
    return nil
  end
  local repo, branch = baseRepo()
  local up, e = require("sysupgrade").check(repo, branch)
  if not up then warn("cannot check byteos for updates: " .. e); return nil end
  if up.uptodate then return nil end
  return up
end

local function upgradeBase(up)
  local sysupgrade = require("sysupgrade")
  header("Retrieving byteos " .. up.version .. " from " .. up.repo .. "...")
  local ok, e = sysupgrade.download(up, progress)
  if not ok then
    term.write("\n")
    err("failed to retrieve byteos: " .. e)
    info("the base system was not changed")
    return false
  end
  progress(("downloaded %d file%s"):format(up.downloaded, up.downloaded == 1 and "" or "s"), 1)
  term.write("\n")
  header("Upgrading byteos...")
  ok, e = sysupgrade.apply(up, function(label, frac) progress("upgrading " .. label, frac) end)
  if not ok then term.write("\n"); err(e); return false end
  progress(("upgraded byteos to %s"):format(up.version), 1)
  term.write("\n")
  for _, path in ipairs(up.pacnew) do
    warn(path .. " installed as " .. path .. ".new")
  end
  return true
end

local function upgrade()
  sync()
  header("Starting full system upgrade...")
  local base = checkBase()
  local outdated = {}
  for _, e_ in ipairs(fs.list(LOCAL_DIR) or {}) do
    local n = e_:gsub("/$", "")
    local meta = findInRepos(n)
    if meta and meta.version ~= installedVersion(n) then outdated[#outdated + 1] = meta end
  end
  if not base and #outdated == 0 then info(" there is nothing to do"); return 0 end

  local names = {}
  if base then names[1] = "byteos-" .. base.version end
  for _, m in ipairs(outdated) do names[#names + 1] = m.name .. "-" .. m.version end
  if not confirmPackages(names, "Proceed with installation?") then return 1 end

  local ok = true
  if base then ok = upgradeBase(base) end
  if ok and #outdated > 0 then ok = installAll(outdated) end
  if base and ok then
    term.cwrite(T.accent, ":: ")
    term.cwrite(T.bright, "byteos was upgraded; reboot to start the new version\n")
  end
  return ok and 0 or 1
end

local function rollback()
  local sysupgrade = require("sysupgrade")
  if not sysupgrade.canRollback() then err("there is no byteos upgrade to roll back"); return 1 end
  if not confirm("Restore byteos from before the last upgrade?") then return 1 end
  sysupgrade.rollback()
  info("previous byteos restored; reboot to use it")
  return 0
end

-- Packages that -R refuses to remove (HoldPkg in pacman.conf).
local function held()
  local set = { byteos = true }
  for n in ((readRepos().options or {}).HoldPkg or ""):gmatch("%S+") do set[n] = true end
  return set
end

local function remove(targets)
  if #targets == 0 then err("no targets specified (use -h for help)"); return 1 end
  local hold = held()
  for _, pkg in ipairs(targets) do
    if not isInstalled(pkg) then err("target not found: " .. pkg); return 1 end
    if hold[pkg] then
      err(pkg .. " is part of the base system and cannot be removed (HoldPkg)")
      return 1
    end
  end
  local names = {}
  for _, pkg in ipairs(targets) do names[#names + 1] = pkg .. "-" .. (installedVersion(pkg) or "?") end
  info("checking dependencies...")
  if not confirmPackages(names, "Do you want to remove these packages?") then return 1 end
  header("Processing package changes...")
  for i, pkg in ipairs(targets) do removePackage(pkg, i, #targets) end
  return 0
end

ensureDirs()
local rest = {}
for _, a in ipairs(args) do
  if a == "--noconfirm" then NOCONFIRM = true else rest[#rest + 1] = a end
end
local op = rest[1]
local targets = { table.unpack(rest, 2) }

if not op or op == "-h" or op == "--help" then
  usage()
  return op and 0 or 1
elseif op == "-Syu" or op == "-Su" then
  return upgrade()
elseif op == "-Sy" then
  sync()
  if #targets > 0 then return install(targets) end
  return 0
elseif op == "--rollback" then
  return rollback()
elseif op == "-S" then
  return install(targets)
elseif op == "-R" then
  return remove(targets)
elseif op == "-Q" then
  if targets[1] == "-i" or targets[1] == "i" then queryInfo(targets[2]) else queryAll() end
elseif op == "-Qi" then
  queryInfo(targets[1])
elseif op == "-Ss" then
  search(targets[1])
else
  err("invalid option '" .. op .. "' (use -h for help)"); return 1
end
return 0
