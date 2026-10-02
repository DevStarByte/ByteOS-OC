--[[
  /lib/bytebios.lua - the "bytebios" package: ByteBIOS on the EEPROM.
  Its source is /boot/eeprom.lua, which is part of byteos, so `pacman -Syu`
  keeps it current. Installing the package means flashing that file.

    bytebios.status()   -> state, info
        state: "none"     no EEPROM in the computer
               "foreign"  another BIOS (e.g. the stock Lua BIOS) is flashed
               "current"  ByteBIOS matches /boot/eeprom.lua
               "outdated" ByteBIOS differs from /boot/eeprom.lua
        info:  { installed = version|nil, available = version|nil }
    bytebios.flash()    -> true | nil, reason
    bytebios.restore()  -> true | nil, reason   put the previous BIOS back

  The BIOS that was on the EEPROM before ByteBIOS is saved the first time,
  so `pacman -R bytebios` can restore it. The boot address stored in the
  EEPROM's data is used the same way by both BIOSes and is kept.
]]--

local fs = kernel.fs

local bytebios = {}

local SOURCE = "/boot/eeprom.lua"
local ORIG   = "/var/lib/pacman/byteos/eeprom.orig"  -- the BIOS from before ByteBIOS

local function eeprom()
  local addr = component.list("eeprom")()
  return addr and component.proxy(addr)
end

-- ByteBIOS shows its version on the boot screen: say(..., "ByteBIOS 1.0", ...)
local function version(code)
  return code and code:match('"ByteBIOS (%d[%d%.]*)"')
end

local function readIf(path)
  if fs.exists(path) then return fs.readAll(path) end
end

function bytebios.status()
  local e = eeprom()
  if not e then return "none", {} end
  local cur, src = e.get(), readIf(SOURCE)
  local info = { installed = version(cur), available = version(src) }
  if not info.installed then return "foreign", info end
  if src and cur ~= src then return "outdated", info end
  return "current", info
end

-- Write `code` and read it back; on a mismatch put `old` back.
local function write(e, code, old)
  pcall(e.set, code)
  if e.get() == code then return true end
  if old then pcall(e.set, old) end
  return nil, "the EEPROM did not accept the new code (is it read-only?); nothing was changed"
end

function bytebios.flash()
  local e = eeprom()
  if not e then return nil, "this computer has no EEPROM" end
  local code = readIf(SOURCE)
  if not version(code) then return nil, SOURCE .. " is missing or not ByteBIOS" end
  local ok, perr = load(code, "=bytebios", "t", {})
  if not ok then return nil, "ByteBIOS does not compile: " .. tostring(perr) end
  if #code > e.getSize() then
    return nil, ("ByteBIOS is %d bytes, the EEPROM holds only %d"):format(#code, e.getSize())
  end

  local old = e.get()
  if not version(old) and not fs.exists(ORIG) then
    if not fs.exists("/var/lib/pacman/byteos") then fs.makeDirectory("/var/lib/pacman/byteos") end
    fs.writeAll(ORIG, old)
    fs.writeAll(ORIG .. ".label", e.getLabel() or "EEPROM")
  end

  local done, werr = write(e, code, old)
  if not done then return nil, werr end
  pcall(e.setLabel, "ByteBIOS")
  -- ByteBIOS boots straight from the address in the EEPROM data
  if (e.getData() or "") == "" and _G.bootfs then pcall(e.setData, _G.bootfs.address) end
  return true
end

function bytebios.canRestore() return fs.exists(ORIG) end

function bytebios.restore()
  local e = eeprom()
  if not e then return nil, "this computer has no EEPROM" end
  local old = readIf(ORIG)
  if not old then return nil, "the previous BIOS was not saved, so it cannot be restored" end
  local done, werr = write(e, old, e.get())
  if not done then return nil, werr end
  pcall(e.setLabel, readIf(ORIG .. ".label") or "EEPROM")
  fs.remove(ORIG); fs.remove(ORIG .. ".label")
  return true
end

return bytebios
