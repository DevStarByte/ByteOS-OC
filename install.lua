--[[
  install.lua - ByteOS installer
  Put it next to the ByteOS files (e.g. on a floppy) and run it under OpenOS:
    lua install.lua

  What it does:
    1. asks for the source filesystem (where the ByteOS files are) and the
       target filesystem
    2. erases EVERYTHING on the target (after asking)
    3. copies /init.lua, /boot, /sbin, /lib, /bin, /etc, /home, /var
    4. optionally flashes ByteBIOS onto the EEPROM and sets the boot address
    5. asks you to reboot

  Once ByteOS runs, it updates itself with `sudo pacman -Syu`.
]]--

local component = require and require("component") or _G.component

-- OpenOS provides io; prompts are read with io.read.
local function ask(msg, default)
  io.write(msg)
  if default then io.write(" [" .. default .. "]") end
  io.write(": ")
  io.flush()
  local line = io.read() or ""
  line = line:gsub("%s+$", "")
  if line == "" then return default end
  return line
end

local function confirm(msg)
  local a = ask(msg .. " (yes/no)", "no")
  return a == "yes" or a == "y"
end

local function listFs()
  print("Filesystems:")
  for addr in component.list("filesystem") do
    local p = component.proxy(addr)
    local label = (p.getLabel and p.getLabel()) or "<no label>"
    local total = p.spaceTotal() or 0
    local used  = p.spaceUsed()  or 0
    print(string.format("  %s  %-12s  %6d / %6d KiB  %s",
      addr:sub(1,8), label,
      math.floor(used/1024), math.floor(total/1024),
      p.isReadOnly() and "ro" or "rw"))
  end
end

local function pickFs(prompt)
  while true do
    listFs()
    local s = ask(prompt .. " (address or prefix)")
    if s then
      for addr in component.list("filesystem") do
        if addr:sub(1, #s) == s then return component.proxy(addr) end
      end
    end
    print("Not found, try again.")
  end
end

local function joinPath(a, b)
  if a:sub(-1) == "/" then return a .. b end
  return a .. "/" .. b
end

local function copyFile(srcFs, srcPath, dstFs, dstPath)
  local fh = srcFs.open(srcPath, "r")
  if not fh then error("cannot read: " .. srcPath) end
  local oh = dstFs.open(dstPath, "w")
  if not oh then srcFs.close(fh); error("cannot write: " .. dstPath) end
  while true do
    local chunk = srcFs.read(fh, 4096)
    if not chunk then break end
    dstFs.write(oh, chunk)
  end
  srcFs.close(fh); dstFs.close(oh)
end

local function copyTree(srcFs, srcRoot, dstFs, dstRoot)
  if srcFs.isDirectory(srcRoot) then
    if not dstFs.exists(dstRoot) then dstFs.makeDirectory(dstRoot) end
    for _, name in ipairs(srcFs.list(srcRoot) or {}) do
      local clean = name:gsub("/$", "")
      copyTree(srcFs, joinPath(srcRoot, clean), dstFs, joinPath(dstRoot, clean))
    end
  else
    io.write("  + " .. dstRoot .. "\n"); io.flush()
    copyFile(srcFs, srcRoot, dstFs, dstRoot)
  end
end

local function wipe(dstFs)
  for _, name in ipairs(dstFs.list("/") or {}) do
    local p = "/" .. name:gsub("/$", "")
    print("  - " .. p)
    dstFs.remove(p)
  end
end

-- ====== main ======
print("==========================================")
print(" ByteOS Installer")
print("==========================================")
print()

local src = pickFs("Source filesystem (where are the ByteOS files?)")
local srcRoot = ask("Path on the source that contains ByteOS", "/")
if not src.exists(joinPath(srcRoot, "init.lua")) then
  print("Error: " .. joinPath(srcRoot, "init.lua") .. " does not exist.")
  return
end
if not src.exists(joinPath(srcRoot, "boot")) then
  print("Error: " .. joinPath(srcRoot, "boot") .. " is missing.")
  return
end

print()
local dst = pickFs("Target filesystem (the disk for ByteOS)")
if dst.isReadOnly() then print("The target is read-only, aborting."); return end
if dst.address == src.address then print("Source and target are the same disk, aborting."); return end

print()
print("WARNING: the target " .. dst.address:sub(1,8) .. " will be ERASED COMPLETELY.")
if not confirm("Continue?") then print("Aborted."); return end

print("Erasing the target...")
wipe(dst)

print("Copying ByteOS...")
local TOP = { "init.lua", "boot", "sbin", "lib", "bin", "etc", "home", "var" }
for _, name in ipairs(TOP) do
  local sp = joinPath(srcRoot, name)
  if src.exists(sp) then
    copyTree(src, sp, dst, "/" .. name)
  else
    print("  (skipped, not in the source: " .. sp .. ")")
  end
end

dst.setLabel("ByteOS")
print("Files copied.")
print()

-- EEPROM
local eepromAddr = component.list("eeprom")()
if eepromAddr then
  if confirm("Flash ByteBIOS onto the EEPROM and set the boot address now?") then
    local biosPath = joinPath(srcRoot, "boot/eeprom.lua")
    local fh = src.open(biosPath, "r")
    local code = ""
    while true do
      local c = src.read(fh, 4096); if not c then break end
      code = code .. c
    end
    src.close(fh)
    local eep = component.proxy(eepromAddr)
    eep.set(code)
    eep.setLabel("ByteBIOS")
    eep.setData(dst.address)
    print("EEPROM flashed, boot address = " .. dst.address:sub(1,8))
  end
end

print()
print("Done. Reboot to start ByteOS:  reboot")
