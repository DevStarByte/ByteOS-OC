--[[
  hypridle - does something when nobody touched Hyprbyte for a while

  Reads ~/.config/hypr/hypridle.conf (else /etc/hypr/hypridle.conf):
    listener = 300, hyprlock                 lock after five minutes
    listener = 60, notify-send "still there?"
  Start it with Hyprbyte: exec-once = hypridle.
]]--
local hypr = package.loaded["hyprbyte.state"]
if not hypr or not hypr.lastInput then print("hypridle: Hyprbyte 1.2 or newer is not running"); return 1 end
local own = (_G.HOME or "/") .. "/.config/hypr/hypridle.conf"
local path = fs.exists(own) and own or "/etc/hypr/hypridle.conf"

local listeners = {}
for line in (fs.readAll(path) or ""):gmatch("[^\r\n]+") do
  local secs, cmd = line:match("^%s*listener%s*=%s*([%d%.]+)%s*,%s*(.-)%s*$")
  if secs and cmd ~= "" then listeners[#listeners + 1] = { timeout = tonumber(secs), cmd = cmd } end
end
if #listeners == 0 then print("hypridle: no listener in " .. path); return 1 end
print(("watching for idle time: %d listener%s"):format(#listeners, #listeners == 1 and "" or "s"))

local since = hypr.lastInput
while package.loaded["hyprbyte.state"] == hypr do
  if hypr.lastInput ~= since then -- someone is back: everything may run again
    since = hypr.lastInput
    for _, l in ipairs(listeners) do l.fired = false end
  end
  local idle = computer.uptime() - hypr.lastInput
  for _, l in ipairs(listeners) do
    if not l.fired and idle >= l.timeout then
      l.fired = true
      print(("idle %ds: %s"):format(math.floor(idle), l.cmd))
      hypr.dispatchers.spawn(l.cmd)
    end
  end
  k.event.pull(1)
end
return 0
