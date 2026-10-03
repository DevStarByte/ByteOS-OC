--[[
  timedatectl [status]             the time, the time zone, whether it is synced
  timedatectl list-timezones       the time zones ByteOS knows
  timedatectl set-timezone <zone>  e.g. Europe/Berlin (root)
  timedatectl sync                 fetch the real time now (needs an internet card)

  timesyncd (a service) fetches the real time at boot and every hour.
]]--
local clock = require("clock")
local args = arg or {}
local T = term.theme
local cmd = args[1] or "status"

local function row(label, value)
  term.cwrite(T.bright, ("%26s: "):format(label))
  term.write(value .. "\n")
end

if cmd == "status" then
  local t, real = clock.now()
  local name, off, abbr = clock.zone(t)
  if real then
    row("Local time", clock.date("%a %F %T %Z", t))
    row("Universal time", clock.date("%a %F %T UTC", t, true))
  end
  row("Time zone", ("%s (%s, %s)"):format(name, abbr, clock.date("%z", real and t or 0)))
  local since = clock.synced()
  row("System clock synchronized",
    since and ("yes, %d min ago"):format(math.floor((computer.uptime() - since) / 60)) or "no (no internet yet)")
  row("Minecraft world time", os.date("%a %F %T"))
  return 0
elseif cmd == "list-timezones" then
  for _, z in ipairs(clock.zones()) do term.write(z .. "\n") end
  return 0
elseif cmd == "set-timezone" then
  if k.user() ~= "root" then term.write("timedatectl: you need to be root (try sudo)\n"); return 1 end
  local zone = args[2]
  local known = false
  for _, z in ipairs(clock.zones()) do if z == zone then known = true end end
  if not known then term.write("timedatectl: unknown time zone '" .. tostring(zone) .. "' (see list-timezones)\n"); return 1 end
  local ok, err = fs.writeAll("/etc/timezone", zone .. "\n")
  if not ok then term.write("timedatectl: " .. tostring(err) .. "\n"); return 1 end
  return 0
elseif cmd == "sync" then
  if k.user() ~= "root" then term.write("timedatectl: you need to be root (try sudo)\n"); return 1 end
  local ok, err = clock.sync()
  if not ok then term.write("timedatectl: " .. tostring(err) .. "\n"); return 1 end
  term.write(clock.date("%a %F %T %Z") .. "\n")
  return 0
end
term.write("timedatectl: unknown command '" .. cmd .. "'\n")
return 1
