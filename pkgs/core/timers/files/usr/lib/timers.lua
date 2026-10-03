--[[
  /usr/lib/timers.lua - .timer units (see man systemd.timer)

  timerd and the timers command share this module, so the command sees
  when each timer last ran.

    timers.load()          -> { unit, ... } every .timer, sorted by name
    timers.isEnabled(name)  timers.enable(name)  timers.disable(name)
    timers.span("5min")    -> 300
    timers.nextRun(unit)   -> seconds until it runs next, or nil
    timers.tick(report)    start every service whose timer is due (timerd);
                           report(text) hears about each start
    timers.state[name]     -> { last = uptime of the last run, ... }
]]--
local k  = _G.kernel
local fs = k.fs

local timers = { state = {} }
local DIRS    = { "/etc/systemd/system", "/usr/lib/systemd/system" }
local ENABLED = "/etc/systemd/timers"
local UNITS   = { s = 1, sec = 1, m = 60, min = 60, h = 3600, hr = 3600, d = 86400, day = 86400 }
local DAYS    = { sun = 0, mon = 1, tue = 2, wed = 3, thu = 4, fri = 5, sat = 6 }

-- "90", "30s", "5min", "2h", "1d", "1h 30min" -> seconds
function timers.span(text)
  local total, any = 0, false
  for n, unit in tostring(text or ""):gmatch("(%d+)%s*(%a*)") do
    local mult = unit == "" and 1 or UNITS[unit:lower()]
    if not mult then return nil end
    total, any = total + tonumber(n) * mult, true
  end
  return any and total or nil
end

-- OnCalendar=: hourly, daily, weekly, or [Mon,Fri ]HH:MM where HH or MM
-- may be * and MM may be */15 or 00/15 (every 15 minutes).
local function calendar(text)
  text = (text or ""):lower()
  if text == "hourly" then text = "*:00"
  elseif text == "daily" then text = "00:00"
  elseif text == "weekly" then text = "mon 00:00" end
  local days, time = text:match("^([%a,]+)%s+(.+)$")
  local cal = { text = text }
  if days then
    cal.days = {}
    for d in days:gmatch("%a+") do
      local n = DAYS[d:sub(1, 3)]
      if not n then return nil end
      cal.days[n] = true
    end
  else
    time = text
  end
  local h, m = time:match("^([%d%*]+):([%d%*/]+)$")
  if not h then return nil end
  cal.hour = h ~= "*" and tonumber(h) or nil
  local first, step = m:match("^([%d%*]+)/(%d+)$")
  if first then
    cal.minute, cal.step = first == "*" and 0 or tonumber(first), tonumber(step)
  elseif m ~= "*" then
    cal.minute = tonumber(m)
  end
  return cal
end

-- local minute-of-day and weekday for clock time t
local function localTime(t)
  local okc, clock = pcall(require, "clock")
  local off = 0
  if okc then
    local _, real = clock.now()
    if real then off = select(2, clock.zone(t)) end
  end
  local lt = t + off
  return lt % 86400 // 60, (lt // 86400 + 4) % 7 -- 1970-01-01 was a Thursday
end

local function now()
  local okc, clock = pcall(require, "clock")
  if okc then return (clock.now()) end
  return math.floor(os.time())
end

local function matches(cal, t)
  local minute, wday = localTime(t)
  local h, m = minute // 60, minute % 60
  if cal.days and not cal.days[wday] then return false end
  if cal.hour and cal.hour ~= h then return false end
  if cal.step then return m >= cal.minute and (m - cal.minute) % cal.step == 0 end
  if cal.minute and cal.minute ~= m then return false end
  return true
end

local function parse(name, path)
  local u = { name = name, path = path, Unit = name }
  for line in (fs.readAll(path) or ""):gmatch("[^\r\n]+") do
    local key, value = line:match("^%s*([%w]+)%s*=%s*(.-)%s*$")
    if key then u[key] = value end
  end
  u.Unit = u.Unit:gsub("%.service$", "")
  u.boot = timers.span(u.OnBootSec)
  u.every = timers.span(u.OnUnitActiveSec)
  u.calendar = u.OnCalendar and calendar(u.OnCalendar)
  if u.OnCalendar and not u.calendar then u.error = "bad OnCalendar=" .. u.OnCalendar end
  if not (u.boot or u.every or u.calendar or u.error) then u.error = "no OnBootSec, OnUnitActiveSec or OnCalendar" end
  return u
end

function timers.load()
  local list, seen = {}, {}
  for _, d in ipairs(DIRS) do
    for _, f in ipairs(fs.list(d) or {}) do
      local n = f:match("^(.+)%.timer$")
      if n and not seen[n] then seen[n] = true; list[#list + 1] = parse(n, d .. "/" .. f) end
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

function timers.isEnabled(name)
  for l in (fs.readAll(ENABLED) or ""):gmatch("[^\r\n]+") do
    if l == name then return true end
  end
  return false
end

local function setEnabled(name, on)
  local out = {}
  for l in (fs.readAll(ENABLED) or ""):gmatch("[^\r\n]+") do
    if l ~= name then out[#out + 1] = l end
  end
  if on then out[#out + 1] = name end
  local ok, err = fs.writeAll(ENABLED, table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
  timers.state[name] = nil
  return ok, err
end
function timers.enable(name) return setEnabled(name, true) end
function timers.disable(name) return setEnabled(name, false) end

-- the uptime a monotonic timer runs at next, or nil
local function dueAt(u, st)
  if st.last then return u.every and st.last + u.every end
  if u.boot then return u.boot end
  if u.every then return (st.loaded or computer.uptime()) + u.every end
end

-- seconds until the timer runs next (nil: never again, or not enabled)
function timers.nextRun(u)
  local st = timers.state[u.name] or {}
  local best
  local at = dueAt(u, st)
  if at then best = math.max(0, at - computer.uptime()) end
  if u.calendar then
    local t = now()
    local start = t - t % 60 + 60
    for i = 0, 8 * 1440 do
      if matches(u.calendar, start + i * 60) then
        local s = start + i * 60 - t
        if not best or s < best then best = s end
        break
      end
    end
  end
  return best
end

-- Start the services of every enabled timer that is due.
function timers.tick(report)
  local systemd = require("systemd")
  local up, t = computer.uptime(), now()
  local minute = t // 60
  for _, u in ipairs(timers.load()) do
    if timers.isEnabled(u.name) and not u.error then
      local st = timers.state[u.name] or { loaded = up }
      timers.state[u.name] = st
      local due = false
      local at = dueAt(u, st)
      if at and up >= at then due = true end
      if u.calendar and st.minute ~= minute and matches(u.calendar, t) then
        st.minute, due = minute, true
      end
      if due then
        st.last, st.lastClock = up, t
        local ok, err = systemd.start(u.Unit)
        st.result = ok and "started" or tostring(err)
        if report then report(("%s.timer: %s %s.service%s"):format(u.name, ok and "started" or "failed to start",
          u.Unit, ok and "" or (": " .. tostring(err)))) end
      end
    end
  end
end

return timers
