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

-- Tiny early console (dmesg-style: dim timestamp, then the message)
local gpu    = component.proxy(component.list("gpu")())
local screen = component.list("screen")()
if gpu and screen then gpu.bind(screen) end
local W, H = gpu.getResolution()
local T0 = computer.uptime()
local cy = 1
gpu.setBackground(0x000000)
gpu.fill(1, 1, W, H, " ")

local function kprint(msg, color)
  msg = tostring(msg)
  local stamp = ("[%8.3f] "):format(computer.uptime() - T0)
  gpu.setForeground(0x8A96A8)
  gpu.set(1, cy, stamp)
  gpu.setForeground(color or 0xD8DEE9)
  gpu.set(#stamp + 1, cy, msg)
  gpu.setForeground(0xFFFFFF)
  cy = cy + 1
  if cy > H then
    gpu.copy(1, 2, W, H - 1, 0, -1)
    gpu.fill(1, H, W, 1, " ")
    cy = H
  end
end
_G.kprint = kprint

-- Like kprint, but without the timestamp: used for systemd-style status lines.
-- `parts` is a list of { text, color } pairs drawn left to right.
function _G.kstatus(parts)
  local x = 1
  gpu.fill(1, cy, W, 1, " ")
  for _, p in ipairs(parts) do
    gpu.setForeground(p[2] or 0xD8DEE9)
    gpu.set(x, cy, p[1])
    x = x + ((unicode and unicode.len(p[1])) or #p[1])
  end
  gpu.setForeground(0xFFFFFF)
  cy = cy + 1
  if cy > H then
    gpu.copy(1, 2, W, H - 1, 0, -1)
    gpu.fill(1, H, W, 1, " ")
    cy = H
  end
end

kprint(_G._OSVERSION .. " (" .. _G._OSCODENAME .. ")", 0x1793D1)
kprint("booting from " .. boot.address:sub(1, 8) .. "...")

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

-- If sysupdate just installed a new version and it cannot boot, put the
-- previous files back from its backup (same journal format as the
-- rollback in /bin/sysupdate.lua). Returns true if something was restored.
local function rollbackUpdate()
  local LIB = "/var/lib/sysupdate"
  if not boot.exists(LIB .. "/pending") then return false end
  local list = readFile(LIB .. "/backup.list")
  if not list then return false end
  for op, path in list:gmatch("(%S+) ([^\n]+)") do
    local here, saved = "/" .. path, LIB .. "/backup/" .. path
    if op == "remove" then
      boot.remove(here)
    elseif op == "restore" and boot.exists(saved) then
      boot.remove(here)
      local dir = here:match("^(.*)/[^/]*$")
      if dir and dir ~= "" then boot.makeDirectory(dir) end
      boot.rename(saved, here)
    end
  end
  boot.remove(LIB .. "/pending")
  boot.remove(LIB .. "/backup.list")
  boot.remove(LIB .. "/backup")
  return true
end

-- Kernel panic screen: anything that escapes init ends up here instead of
-- OpenComputers' generic crash screen.
local function panic(trace)
  gpu.setBackground(0x000000); gpu.fill(1, 1, W, H, " ")
  gpu.setBackground(0xF0605A); gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, W, 1, " ")
  local title = " KERNEL PANIC "
  gpu.set(math.max(1, math.floor((W - #title) / 2) + 1), 1, title)
  gpu.setBackground(0x000000)
  local y = 3
  local function line(s, color)
    if y > H - 2 then return end
    gpu.setForeground(color)
    while #s > 0 and y <= H - 2 do
      gpu.set(2, y, s:sub(1, W - 2)); s = s:sub(W - 1); y = y + 1
    end
  end
  line(_G._OSVERSION .. " has stopped to protect your data.", 0xD8DEE9)
  y = y + 1
  for l in (trace .. "\n"):gmatch("([^\n]*)\n") do
    line((l:gsub("\t", "  ")), y == 5 and 0xF0605A or 0x8A96A8)
  end
  local okRb, restored = pcall(rollbackUpdate)
  if okRb and restored then
    gpu.setForeground(0x5FD068)
    gpu.set(2, H - 1, "The last update failed to boot; the previous version was restored.")
  end
  gpu.setForeground(0x8A96A8)
  gpu.set(2, H, "Press any key to reboot.")
  while true do
    local ev = computer.pullSignal()
    if ev == "key_down" then computer.shutdown(true) end
  end
end

local ok, err = xpcall(function()
  kprint("loading kernel...")
  dofileBoot("/boot/kernel.lua")
  kprint("starting init...")
  dofileBoot("/sbin/init.lua")
end, function(e)
  -- capture the traceback here, while the failing stack still exists
  return (debug and debug.traceback) and debug.traceback(tostring(e), 2) or tostring(e)
end)
if not ok then panic(err) end
