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
local w, h = 0, 0
local function g(m, ...) return component.invoke(gpu, m, ...) end
-- centred line of text on row y (no-op without a screen)
local function say(y, s, fg)
  if w == 0 then return end
  g("setForeground", fg)
  g("fill", 1, y, w, 1, " ")
  g("set", math.floor((w - #s) / 2) + 1, y, s)
end
if gpu and screen then
  g("bind", screen)
  w, h = g("maxResolution")
  g("setResolution", w, h)
  g("setBackground", 0x000000)
  g("fill", 1, 1, w, h, " ")
  say(math.floor(h / 2) - 1, "ByteBIOS 1.0", 0x1793D1)
  say(math.floor(h / 2) + 1, "Looking for a bootable disk...", 0x8A96A8)
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
  if w == 0 then error("no bootable medium found - insert a ByteOS disk", 0) end
  say(math.floor(h / 2) + 1, "No bootable disk found.", 0xF0605A)
  say(math.floor(h / 2) + 2, "Insert a ByteOS disk and press any key.", 0x8A96A8)
  repeat until computer.pullSignal() == "key_down"
  computer.shutdown(true)
end

-- Hand off control to /init.lua
init()
