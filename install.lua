--[[
  install.lua - ByteOS-Installer
  Auf einer Floppy oder per `pastebin get` neben den ByteOS-Quellen platzieren.
  Wird unter OpenOS ausgeführt:  lua install.lua

  Was er tut:
    1. fragt Quell-FS (wo die ByteOS-Dateien liegen) und Ziel-FS ab
    2. löscht ALLES im Ziel  (du bekommst einen Prompt)
    3. kopiert /init.lua, /boot, /sbin, /lib, /bin, /etc, /home, /var rekursiv
    4. (optional) flasht ByteBIOS aufs EEPROM und setzt Boot-Adresse aufs Ziel
    5. fordert zum Reboot auf
]]--

local component = require and require("component") or _G.component
local computer  = require and require("computer")  or _G.computer
local fs        = component.proxy(component.list("filesystem")()) -- nur als fallback
local term

-- OpenOS hat term & io. Wir nutzen io.read fürs Prompting.
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
  print("Verfügbare Filesysteme:")
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
    local s = ask(prompt .. " (Adresse oder Präfix)")
    if s then
      for addr in component.list("filesystem") do
        if addr:sub(1, #s) == s then return component.proxy(addr) end
      end
    end
    print("Nicht gefunden, nochmal.")
  end
end

local function joinPath(a, b)
  if a:sub(-1) == "/" then return a .. b end
  return a .. "/" .. b
end

local function copyFile(srcFs, srcPath, dstFs, dstPath)
  local fh = srcFs.open(srcPath, "r")
  if not fh then error("kann nicht lesen: " .. srcPath) end
  local oh = dstFs.open(dstPath, "w")
  if not oh then srcFs.close(fh); error("kann nicht schreiben: " .. dstPath) end
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

-- ====== los gehts ======
print("==========================================")
print(" ByteOS Installer")
print("==========================================")
print()

local src = pickFs("Quell-Filesystem (wo liegt das ByteOS-Repo / die Floppy?)")
local srcRoot = ask("Pfad innerhalb der Quelle, der ByteOS enthält", "/")
if not src.exists(joinPath(srcRoot, "init.lua")) then
  print("Fehler: " .. joinPath(srcRoot, "init.lua") .. " existiert nicht.")
  return
end
if not src.exists(joinPath(srcRoot, "boot")) then
  print("Fehler: " .. joinPath(srcRoot, "boot") .. " fehlt.")
  return
end

print()
local dst = pickFs("Ziel-Filesystem (Festplatte fuer ByteOS)")
if dst.isReadOnly() then print("Ziel ist schreibgeschuetzt, abbruch."); return end
if dst.address == src.address then print("Quelle = Ziel, abbruch."); return end

print()
print("ACHTUNG: Das Ziel " .. dst.address:sub(1,8) .. " wird KOMPLETT gelöscht.")
if not confirm("Wirklich fortfahren?") then print("Abgebrochen."); return end

print("Loesche Ziel ...")
wipe(dst)

print("Kopiere ByteOS ...")
local TOP = { "init.lua", "boot", "sbin", "lib", "bin", "etc", "home", "var" }
for _, name in ipairs(TOP) do
  local sp = joinPath(srcRoot, name)
  if src.exists(sp) then
    copyTree(src, sp, dst, "/" .. name)
  else
    print("  (uebersprungen, nicht in Quelle: " .. sp .. ")")
  end
end

dst.setLabel("ByteOS")
print("Dateien kopiert.")
print()

-- EEPROM
local eepromAddr = component.list("eeprom")()
if eepromAddr then
  if confirm("ByteBIOS jetzt aufs EEPROM flashen und Bootadresse setzen?") then
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
    print("EEPROM geflasht, Bootadresse = " .. dst.address:sub(1,8))
  end
end

print()
print("Fertig. Bitte rebooten:  reboot")
