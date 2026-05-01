--[[
  /init.lua - ByteOS entry point
  The EEPROM (ByteBIOS) loads and executes this file.
  It bootstraps the kernel, then transfers control to /sbin/init.
]]--

_G._OSVERSION   = "ByteOS 1.0.0"
_G._OSCODENAME  = "Iron"
_G._BOOTADDRESS = (computer.getBootAddress and computer.getBootAddress()) or nil

local component = component
local computer  = computer

-- Locate the boot filesystem proxy. Prefer the address the BIOS told us;
-- otherwise pick the first FS that actually contains /init.lua (= us).
local function findBootFs()
  if _G._BOOTADDRESS and _G._BOOTADDRESS ~= "" then
    local ok, p = pcall(component.proxy, _G._BOOTADDRESS)
    if ok and p and p.exists("/init.lua") then return p end
  end
  for addr in component.list("filesystem") do
    local ok, p = pcall(component.proxy, addr)
    if ok and p and p.exists("/init.lua") and p.exists("/boot/kernel.lua") then
      _G._BOOTADDRESS = addr
      if computer.setBootAddress then pcall(computer.setBootAddress, addr) end
      return p
    end
  end
  error("ByteOS: no filesystem with /init.lua + /boot/kernel.lua found", 0)
end

local boot = findBootFs()
_G.bootfs  = boot

-- Tiny early console
local gpu    = component.proxy(component.list("gpu")())
local screen = component.list("screen")()
if gpu and screen then gpu.bind(screen) end
local W, H = gpu.getResolution()
local cy = 1
local function kprint(msg, color)
  if color then gpu.setForeground(color) end
  gpu.set(1, cy, tostring(msg) .. string.rep(" ", W - #tostring(msg)))
  gpu.setForeground(0xFFFFFF)
  cy = cy + 1
  if cy > H then
    gpu.copy(1, 2, W, H - 1, 0, -1)
    gpu.fill(1, H, W, 1, " ")
    cy = H
  end
end
_G.kprint = kprint

kprint("[    0.000] " .. _G._OSVERSION .. " (" .. _G._OSCODENAME .. ")", 0x66CCFF)
kprint("[    0.001] booting from " .. boot.address:sub(1, 8) .. "...")

-- Read a file from the boot filesystem
local function readFile(path)
  local h, err = boot.open(path, "r")
  if not h then return nil, err end
  local data = ""
  while true do
    local chunk = boot.read(h, math.huge)
    if not chunk then break end
    data = data .. chunk
  end
  boot.close(h)
  return data
end
_G.readFile = readFile

-- Load and execute a Lua file
local function dofileBoot(path)
  local data, err = readFile(path)
  if not data then error("cannot read " .. path .. ": " .. tostring(err), 0) end
  local fn, lerr = load(data, "=" .. path, "t", _G)
  if not fn then error("parse error in " .. path .. ": " .. lerr, 0) end
  return fn()
end
_G.dofileBoot = dofileBoot

kprint("[    0.010] loading kernel...")
dofileBoot("/boot/kernel.lua")

kprint("[    0.050] starting init...")
dofileBoot("/sbin/init.lua")
