--[[
  timers - services that start on a schedule

    timers                     every timer: when it runs next and last ran
    timers enable <name>       turn a timer on (root)
    timers disable <name>      turn it off (root)
    timers start <name>        run its service now (root)

  A timer is /etc/systemd/system/<name>.timer; see man systemd.timer.
  timerd (a service) does the starting; pacman enabled it.
]]--
local timers = require("timers")
local systemd = require("systemd")
local T = term.theme
local args = arg or {}
local cmd, name = args[1], args[2] and args[2]:gsub("%.timer$", "")

local function fail(msg) term.cwrite(T.err, "timers: "); term.write(msg .. "\n"); return 1 end
local function span(s)
  s = math.floor(s)
  if s < 60 then return s .. "s" end
  if s < 3600 then return ("%dmin %ds"):format(s // 60, s % 60) end
  if s < 86400 then return ("%dh %dmin"):format(s // 3600, s % 3600 // 60) end
  return ("%dd %dh"):format(s // 86400, s % 86400 // 3600)
end
local function find(n)
  for _, u in ipairs(timers.load()) do if u.name == n then return u end end
end

if not cmd or cmd == "list" then
  local list = timers.load()
  if #list == 0 then term.write("No timers. Write one in /etc/systemd/system (man systemd.timer).\n"); return 0 end
  term.cwrite(T.bright, ("%-16s %-8s %-12s %-12s %s\n"):format("TIMER", "ENABLED", "NEXT", "LAST", "STARTS"))
  for _, u in ipairs(list) do
    local on = timers.isEnabled(u.name)
    local st = timers.state[u.name] or {}
    local nxt = u.error and u.error or (on and timers.nextRun(u))
    term.write(("%-16s "):format(u.name))
    term.cwrite(on and T.green or T.muted, ("%-8s "):format(on and "yes" or "no"))
    term.write(("%-12s %-12s %s.service\n"):format(
      type(nxt) == "number" and ("in " .. span(nxt)) or (nxt or "-"),
      st.last and (span(computer.uptime() - st.last) .. " ago") or "-", u.Unit))
  end
  if systemd.status("timerd").active ~= "active" then
    term.cwrite(T.yellow, "timerd is not running: sudo systemctl enable --now timerd\n")
  end
  return 0
end

if not name then return fail("which timer?") end
local u = find(name)
if not u then return fail("no timer " .. name .. " (/etc/systemd/system/" .. name .. ".timer)") end
if k.user() ~= "root" then return fail("only root may do that (try sudo)") end
if cmd == "enable" then
  if u.error then return fail(name .. ".timer: " .. u.error) end
  timers.enable(name)
  term.write("Enabled " .. name .. ".timer\n")
elseif cmd == "disable" then
  timers.disable(name)
  term.write("Disabled " .. name .. ".timer\n")
elseif cmd == "start" then
  local ok, err = systemd.start(u.Unit)
  if not ok then return fail(tostring(err)) end
  term.write("Started " .. u.Unit .. ".service\n")
else
  return fail("unknown command " .. cmd)
end
return 0
