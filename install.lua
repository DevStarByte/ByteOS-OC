--[[
  install.lua - ByteOS installer (runs under OpenOS)

  Over the internet (needs an internet card). Boot the OpenOS floppy and
  type in its shell:

    wget -f https://raw.githubusercontent.com/DevStarByte/ByteOS-OC/master/install.lua /tmp/install.lua
    /tmp/install.lua

  Or from a disk that holds the ByteOS files: run this file from there and
  choose "disk" as the source.

  What it does:
    1. asks where ByteOS comes from (the internet or a disk) and which disk
       to install it on
    2. erases EVERYTHING on that disk (after asking)
    3. puts ByteOS on it: /init.lua /boot /sbin /lib /bin /etc /home /var /usr
    4. remembers what it installed, so `sudo pacman -Syu` later only fetches
       what changed and keeps the /etc files you leave alone up to date
    5. optionally flashes ByteBIOS onto the EEPROM (the old BIOS is saved,
       `pacman -R bytebios` puts it back) and points it at the new disk
    6. reboots
]]--

local REPO, BRANCH = "DevStarByte/ByteOS-OC", "master"
local TOP = { "init.lua", "boot", "sbin", "lib", "bin", "etc", "home", "var", "usr" }
local LIB = "/var/lib/pacman/byteos"

local component = require("component")
local computer  = require("computer")
local sleep = os.sleep or function() end

-- ---- prompts ---------------------------------------------------------------
local function ask(msg, default)
  io.write(msg)
  if default then io.write(" [" .. default .. "]") end
  io.write(": ")
  if io.flush then io.flush() end
  local line = (io.read() or ""):gsub("%s+$", "")
  if line == "" then return default end
  return line
end

local function confirm(msg, default)
  local a = ask(msg .. " (yes/no)", default and "yes" or "no"):lower()
  return a == "yes" or a == "y"
end

local function fail(msg)
  print("Error: " .. msg)
  print("Nothing was installed.")
  os.exit(1)
end

-- ---- disks -----------------------------------------------------------------
local function describe(p)
  local label = (p.getLabel and p.getLabel()) or "no label"
  return ("%s  %-12s %5d KiB free  %s"):format(p.address:sub(1, 8), label,
    math.floor(((p.spaceTotal() or 0) - (p.spaceUsed() or 0)) / 1024), p.isReadOnly() and "read-only" or "")
end

-- Disks that could take ByteOS: writable, not the temp disk, not the one
-- OpenOS runs from.
local function candidates(exclude)
  local running = computer.getBootAddress and computer.getBootAddress()
  local tmp = computer.tmpAddress and computer.tmpAddress()
  local out = {}
  for addr in component.list("filesystem") do
    local p = component.proxy(addr)
    if addr ~= tmp and addr ~= running and addr ~= exclude and not p.isReadOnly() then out[#out + 1] = p end
  end
  table.sort(out, function(a, b) return a.address < b.address end)
  return out
end

local function choose(list, what)
  if #list == 0 then fail("there is no disk to use as " .. what) end
  for i, p in ipairs(list) do print(("  %d) %s"):format(i, describe(p))) end
  while true do
    local n = tonumber(ask("Which one is " .. what, #list == 1 and "1" or nil))
    if n and list[n] then return list[n] end
    print("Please type one of the numbers.")
  end
end

local function parent(p) return p:match("^(.*)/[^/]*$") or "" end
local function writeFile(fs, path, data)
  local dir = parent(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDirectory(dir) end
  local h, err = fs.open(path, "w")
  if not h then fail("cannot write " .. path .. ": " .. tostring(err)) end
  local i = 1
  while i <= #data do
    fs.write(h, data:sub(i, i + 8191))
    i = i + 8192
  end
  fs.close(h)
end

-- ---- the internet ----------------------------------------------------------
local function http(url, accept)
  local inet = component.list("internet")() and component.proxy(component.list("internet")())
  if not inet then fail("no internet card in this computer") end
  local ok, h, reason = pcall(inet.request, url, nil, { ["User-Agent"] = "ByteOS-installer", ["Accept"] = accept or "*/*" })
  if not ok or not h then return nil, tostring(ok and reason or h) end
  for _ = 1, 400 do
    local okc, done, why = pcall(h.finishConnect)
    if not okc or done == nil then h.close(); return nil, tostring(okc and why or done) end
    if done then break end
    sleep(0.05)
  end
  local code
  for _ = 1, 400 do
    code = h.response()
    if code then break end
    sleep(0.05)
  end
  if code ~= 200 then
    h.close()
    if code == 403 or code == 429 then return nil, "GitHub's rate limit is reached; try again in an hour" end
    return nil, "HTTP " .. tostring(code)
  end
  local parts = {}
  while true do
    local okr, chunk, rerr = pcall(h.read, 8192)
    if not okr then h.close(); return nil, tostring(chunk) end
    if chunk == nil then
      h.close()
      if rerr then return nil, tostring(rerr) end
      return table.concat(parts)
    end
    if #chunk > 0 then parts[#parts + 1] = chunk else sleep(0.05) end
  end
end

local function inTop(path)
  local first = path:match("^([^/]+)")
  for _, t in ipairs(TOP) do
    if first == t then return true end
  end
  return false
end

-- The newest ByteOS on GitHub: { commit, files = { { path, size, sha } }, read(path) }
local function internetSource()
  local api = "https://api.github.com/repos/" .. REPO
  print("Asking GitHub for the newest ByteOS...")
  local commit, err = http(api .. "/commits/" .. BRANCH, "application/vnd.github.sha")
  commit = commit and commit:match("^%s*(%x+)%s*$")
  if not commit then fail("cannot reach GitHub: " .. tostring(err)) end
  local json
  json, err = http(api .. "/git/trees/" .. commit .. "?recursive=1")
  if not json then fail("cannot list the files: " .. tostring(err)) end
  local files = {}
  for obj in (json:match('"tree"%s*:%s*(%b[])') or ""):gmatch("%b{}") do
    local path = obj:match('"path"%s*:%s*"(.-)"')
    if obj:match('"type"%s*:%s*"blob"') and path and inTop(path) then
      files[#files + 1] = { path = path, sha = obj:match('"sha"%s*:%s*"(%x+)"'),
                            size = tonumber(obj:match('"size"%s*:%s*(%d+)')) }
    end
  end
  if #files == 0 then fail("GitHub sent no file list") end
  local raw = "https://raw.githubusercontent.com/" .. REPO .. "/" .. commit .. "/"
  return {
    commit = commit,
    files = files,
    read = function(path)
      local url = raw .. path:gsub("[^%w%-%._~/]", function(c) return ("%%%02X"):format(c:byte()) end)
      local data, e = http(url)
      if not data then fail(path .. ": " .. tostring(e)) end
      return data
    end,
  }
end

-- ByteOS files on a disk (a floppy, or a copy of the repository).
local function diskSource()
  -- disks with ByteOS at the top are offered; otherwise ask for disk and folder
  local all, found = {}, {}
  for addr in component.list("filesystem") do
    local p = component.proxy(addr)
    all[#all + 1] = p
    if p.exists("/init.lua") and p.exists("/boot/kernel.lua") and p.exists("/sbin/init.lua") then found[#found + 1] = p end
  end
  table.sort(all, function(a, b) return a.address < b.address end)
  table.sort(found, function(a, b) return a.address < b.address end)
  local src, root
  if #found > 0 then
    print("Disks with ByteOS on them:")
    src, root = choose(found, "the source"), ""
  else
    print("No disk has ByteOS at its top level. Which disk holds the files?")
    src = choose(all, "the source")
    root = ask("Folder on that disk that holds ByteOS", "/"):gsub("/$", "")
  end
  if not src.exists(root .. "/init.lua") or not src.exists(root .. "/boot/kernel.lua") then
    fail(root .. "/init.lua or /boot/kernel.lua is missing on that disk")
  end
  local files = {}
  local function walk(path)
    if src.isDirectory(root .. "/" .. path) then
      for _, n in ipairs(src.list(root .. "/" .. path) or {}) do walk((path .. "/" .. n:gsub("/$", "")):gsub("^/", "")) end
    else
      files[#files + 1] = { path = path, size = src.size(root .. "/" .. path) }
    end
  end
  for _, t in ipairs(TOP) do
    if src.exists(root .. "/" .. t) then walk(t) end
  end
  return {
    address = src.address,
    files = files,
    read = function(path)
      local h = src.open(root .. "/" .. path, "r")
      local parts = {}
      while true do
        local c = src.read(h, 8192)
        if not c then break end
        parts[#parts + 1] = c
      end
      src.close(h)
      return table.concat(parts)
    end,
  }
end

-- ---- main ------------------------------------------------------------------
print("==========================================")
print(" ByteOS installer")
print("==========================================")
print()
print("Where should ByteOS come from?")
print("  1) the internet (GitHub, needs an internet card)")
print("  2) a disk with the ByteOS files")
local from = ask("Source", component.list("internet")() and "1" or "2")
local source = from == "2" and diskSource() or internetSource()
print(("%d files to install."):format(#source.files))

print()
print("Install ByteOS on which disk?")
local dst = choose(candidates(source.address), "the target")
local need = 0
for _, f in ipairs(source.files) do need = need + (f.size or 0) end
if dst.spaceTotal() < need + 65536 then
  fail(("that disk is too small: ByteOS needs %d KiB"):format(math.ceil(need / 1024) + 64))
end

print()
print("WARNING: everything on " .. dst.address:sub(1, 8) .. " will be ERASED.")
if not confirm("Continue?", false) then print("Aborted. Nothing was changed."); return end

print("Erasing...")
for _, name in ipairs(dst.list("/") or {}) do dst.remove("/" .. name:gsub("/$", "")) end

print("Installing ByteOS...")
local installed = {}
for i, f in ipairs(source.files) do
  io.write(("\r  (%d/%d) %-40s"):format(i, #source.files, f.path:sub(-40)))
  local data = source.read(f.path)
  if f.size and #data ~= f.size then fail(f.path .. ": got " .. #data .. " bytes, expected " .. f.size) end
  writeFile(dst, "/" .. f.path, data)
  installed[f.path] = data
end
print()

-- What pacman needs to upgrade this system later.
local release = installed["etc/os-release"] or ""
local version = release:match("VERSION_ID=\"?([^\"\r\n]+)") or "?"
if source.commit then
  local state = { "commit " .. source.commit }
  for _, f in ipairs(source.files) do
    if f.sha then state[#state + 1] = f.sha .. " " .. f.path end
  end
  writeFile(dst, LIB .. "/state", table.concat(state, "\n") .. "\n")
  version = version .. ".g" .. source.commit:sub(1, 7)
end
for path, data in pairs(installed) do
  if path:match("^etc/") then writeFile(dst, LIB .. "/pristine/" .. path, data) end
end
local desc = installed["var/lib/pacman/local/byteos/desc"]
if desc then
  writeFile(dst, "/var/lib/pacman/local/byteos/desc", (desc:gsub("version=[^\r\n]*", "version=" .. version)))
end
dst.setLabel("ByteOS")
print("ByteOS " .. version .. " is on " .. dst.address:sub(1, 8) .. ".")

-- ByteBIOS
local eepromAddr = component.list("eeprom")()
if eepromAddr and installed["boot/eeprom.lua"] then
  print()
  if confirm("Flash ByteBIOS onto the EEPROM? (ByteOS also boots with the Lua BIOS)", true) then
    local eeprom = component.proxy(eepromAddr)
    local old = eeprom.get()
    if not old:find("ByteBIOS", 1, true) then
      writeFile(dst, LIB .. "/eeprom.orig", old)
      writeFile(dst, LIB .. "/eeprom.orig.label", eeprom.getLabel() or "EEPROM")
    end
    eeprom.set(installed["boot/eeprom.lua"])
    if eeprom.get() ~= installed["boot/eeprom.lua"] then
      print("The EEPROM did not take ByteBIOS (read-only?); it keeps its BIOS.")
      eeprom.set(old)
    else
      eeprom.setLabel("ByteBIOS")
      print("ByteBIOS flashed; the old BIOS is saved (pacman -R bytebios restores it).")
    end
  end
  component.proxy(eepromAddr).setData(dst.address)
end
if computer.setBootAddress then computer.setBootAddress(dst.address) end

print()
print("Done. Take the OpenOS floppy out; ByteOS boots from " .. dst.address:sub(1, 8) .. ".")
print("At the first start a setup wizard asks for a root password and a user.")
if confirm("Reboot now?", true) then computer.shutdown(true) end
