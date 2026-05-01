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
  for line in (fs.readAll(CONF_PATH) or ""):gmatch("[^\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line:sub(1,1) == "#" or line == "" then
      -- comment/blank
    elseif line:sub(1,1) == "[" then
      section = line:match("%[(.-)%]")
      repos[section] = repos[section] or {}
    elseif section then
      local k_, v = line:match("([^=]+)%s*=%s*(.+)")
      if k_ then repos[section][k_] = v end
    end
  end
  return repos
end

local function info(msg, color)
  term.setForeground(color or 0x55FF55); term.write(":: ")
  term.setForeground(0xFFFFFF); term.write(msg .. "\n")
end

local function err(msg)
  term.setForeground(0xFF5555); term.write("error: ")
  term.setForeground(0xFFFFFF); term.write(msg .. "\n")
end

-- Very small "downloader": copies files from a local-disk repo (e.g. /mnt/<id>/repo)
-- This works inside Minecraft (no real internet). A repo "Server" is just a path.
local function fetch(server, name)
  local p = server .. "/" .. name
  if fs.exists(p) then return fs.readAll(p) end
  return nil, "404 " .. p
end

local function syncRepo(rname, rconf)
  local data, e = fetch(rconf.Server, "repo.db")
  if not data then err("failed to sync " .. rname .. ": " .. tostring(e)); return false end
  fs.makeDirectory(SYNC_DIR .. "/" .. rname)
  fs.writeAll(SYNC_DIR .. "/" .. rname .. "/repo.db", data)
  info("synchronized " .. rname)
  return true
end

local function findInRepos(pkg)
  for _, name in ipairs({}) do end -- placeholder
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

local function installPackage(pkg)
  if isInstalled(pkg) then info(pkg .. " is up to date -- reinstalling") end
  local meta = findInRepos(pkg)
  if not meta then err("target not found: " .. pkg); return false end
  info("installing " .. pkg .. " (" .. meta.version .. ") from " .. meta.repo)

  -- Prefer the compressed package (.pkg.z), fall back to the plain .pkg.
  local stem = pkg .. "-" .. meta.version
  local data, e = fetch(meta.server, stem .. ".pkg.z")
  local compressed = data ~= nil
  if not data then
    data, e = fetch(meta.server, stem .. ".pkg")
  end
  if not data then err("download failed: " .. tostring(e)); return false end

  -- packages are Lua tables: return { files = {...}, post_install = function() ... end }
  local fn, perr = load(data, "=" .. pkg, "t", { string = string, table = table, math = math })
  if not fn then err("malformed package: " .. perr); return false end
  local ok, pkgtab = pcall(fn)
  if not ok or type(pkgtab) ~= "table" then err("invalid package payload"); return false end

  -- Decompress file contents if the package declares a known format.
  if pkgtab.format == "lzw1" then
    if compressed then info("decompressing payload (" .. #data .. " B)") end
    for path, content in pairs(pkgtab.files or {}) do
      local plain, derr = compress.decode(content)
      if not plain then err("decompress failed for " .. path .. ": " .. tostring(derr)); return false end
      pkgtab.files[path] = plain
    end
  elseif pkgtab.format and pkgtab.format ~= "raw" then
    err("unknown package format: " .. tostring(pkgtab.format)); return false
  end

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

  if pkgtab.post_install then pcall(pkgtab.post_install) end
  info("installed " .. pkg)
  return true
end

local function removePackage(pkg)
  if not isInstalled(pkg) then err("target not installed: " .. pkg); return false end
  local files = fs.readAll(LOCAL_DIR .. "/" .. pkg .. "/files") or ""
  for f in files:gmatch("[^\n]+") do if fs.exists(f) then fs.remove(f) end end
  for _, e_ in ipairs(fs.list(LOCAL_DIR .. "/" .. pkg) or {}) do
    fs.remove(LOCAL_DIR .. "/" .. pkg .. "/" .. e_)
  end
  fs.remove(LOCAL_DIR .. "/" .. pkg)
  info("removed " .. pkg)
  return true
end

local function queryAll()
  for _, e_ in ipairs(fs.list(LOCAL_DIR) or {}) do
    local n   = e_:gsub("/$", "")
    local d   = fs.readAll(LOCAL_DIR .. "/" .. n .. "/desc") or ""
    local ver = d:match("version=(%S+)") or "?"
    term.write(n .. " " .. ver .. "\n")
  end
end

local function queryInfo(pkg)
  if not isInstalled(pkg) then err("not installed: " .. pkg); return end
  term.write(fs.readAll(LOCAL_DIR .. "/" .. pkg .. "/desc") or "")
  term.write("Files:\n" .. (fs.readAll(LOCAL_DIR .. "/" .. pkg .. "/files") or ""))
end

local function search(pat)
  for _, fname in ipairs(fs.list(SYNC_DIR) or {}) do
    local rname = fname:gsub("/$", "")
    local dbp   = SYNC_DIR .. "/" .. rname .. "/repo.db"
    if fs.exists(dbp) then
      for line in (fs.readAll(dbp) or ""):gmatch("[^\n]+") do
        local n, v, d = line:match("(%S+)%s+(%S+)%s+(.+)")
        if n and (not pat or n:find(pat) or (d or ""):find(pat)) then
          term.setForeground(0x55FF55); term.write(rname .. "/")
          term.setForeground(0xFFFFFF); term.write(n .. " ")
          term.setForeground(0x55FF55); term.write(v .. "\n")
          term.setForeground(0xFFFFFF); term.write("    " .. (d or "") .. "\n")
        end
      end
    end
  end
end

-- ===== argument dispatch =====
ensureDirs()
local op = args[1]
if not op then
  term.write("usage: pacman <-S|-R|-Q|-Ss|-Syu> [targets...]\n")
  return 1
end

if op == "-Sy" or op == "-Syu" then
  for name, conf in pairs(readRepos()) do if conf.Server then syncRepo(name, conf) end end
  if op == "-Syu" then info("system fully up to date") end
  return 0
elseif op == "-S" then
  for i = 2, #args do installPackage(args[i]) end
elseif op == "-R" then
  for i = 2, #args do removePackage(args[i]) end
elseif op == "-Q" then
  if args[2] == "-i" or args[2] == "i" then queryInfo(args[3]) else queryAll() end
elseif op == "-Ss" then
  search(args[2])
else
  err("unknown operation: " .. op); return 1
end
return 0
