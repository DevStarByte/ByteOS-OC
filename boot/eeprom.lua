--[[
  ByteBIOS - EEPROM bootloader for ByteOS
  Flash this onto an EEPROM with: component.eeprom.set(content)
  It scans all filesystems for /init.lua and boots from the first one found.
]]--

local component = component
local computer  = computer

local function tryInvoke(addr, method, ...)
  local ok, res = pcall(component.invoke, addr, method, ...)
  if ok then return res end
end

local function setBootAddress(addr)
  if component.proxy(component.list("eeprom")()) then
    pcall(component.invoke, component.list("eeprom")(), "setData", addr or "")
  end
end

local function getBootAddress()
  return tryInvoke(component.list("eeprom")(), "getData")
end

-- OpenOS-compatible helpers expected by /init.lua
computer.getBootAddress = getBootAddress
computer.setBootAddress = setBootAddress

-- Try to display something on screen (if available)
local gpu = component.list("gpu")()
local screen = component.list("screen")()
if gpu and screen then
  component.invoke(gpu, "bind", screen)
  local w, h = component.invoke(gpu, "maxResolution")
  component.invoke(gpu, "setResolution", w, h)
  component.invoke(gpu, "setBackground", 0x000000)
  component.invoke(gpu, "setForeground", 0xFFFFFF)
  component.invoke(gpu, "fill", 1, 1, w, h, " ")
  component.invoke(gpu, "set", 1, 1, "ByteBIOS v1.0  ::  loading ByteOS...")
end

-- Find a filesystem with /init.lua
local boot = getBootAddress()
local function loadFrom(addr)
  local handle = tryInvoke(addr, "open", "/init.lua")
  if not handle then return nil end
  local buffer = ""
  repeat
    local chunk = tryInvoke(addr, "read", handle, math.huge)
    buffer = buffer .. (chunk or "")
  until not chunk
  tryInvoke(addr, "close", handle)
  return load(buffer, "=init", "t", _G)
end

local init
if boot and boot ~= "" then
  init = loadFrom(boot)
end

if not init then
  for addr in component.list("filesystem") do
    init = loadFrom(addr)
    if init then
      setBootAddress(addr)
      break
    end
  end
end

if not init then
  error("no bootable medium found - insert a ByteOS disk", 0)
end

-- Hand off control to /init.lua
init()
