-- The clock: calendar maths, time zones with daylight saving time and
-- formatting, checked against the PC's own `date` and its time zone data.
local clock = require("clock")

local function hostDate(zone, t, fmt)
  local h = io.popen(("TZ=%s date -d @%d +'%s'"):format(zone, t, fmt))
  local s = h:read("l")
  h:close()
  return s
end

test("parses an HTTP Date header", function()
  eq(clock.parseHttpDate("Sat, 03 Oct 2026 12:34:56 GMT"), 1791030896)
  eq(clock.parseHttpDate("Thu, 01 Jan 1970 00:00:00 GMT"), 0)
  eq(clock.parseHttpDate("Tue, 29 Feb 2028 23:59:59 GMT"), 1835481599)
  eq(clock.parseHttpDate("garbage"), nil)
end)

test("time zones and DST switches match the PC's tz data", function()
  -- around every switch of 2025-2027 in each rule, plus some plain days
  -- (today's rules only: the clock does not know historic time zone changes)
  local probes = {}
  for _, t in ipairs({ 1743296400, 1761440400, 1774746000, 1792890000,   -- EU 2025/2026 switches
                       1741503600, 1762063200, 1772953200, 1793512800,   -- US
                       1759593600, 1743868800, 1791043200, 1775318400,   -- AU
                       1791030896, 1830297600 }) do
    for _, d in ipairs({ -3601, -1, 0, 1, 3599, 86400 }) do probes[#probes + 1] = t + d end
  end
  for _, zone in ipairs(clock.zones()) do
    put("/etc/timezone", zone .. "\n"); clock.forgetZone()
    for _, t in ipairs(probes) do
      local mine = clock.date("%Y-%m-%d %H:%M:%S %z", t)
      eq(mine, hostDate(zone, t, "%Y-%m-%d %H:%M:%S %z"), zone .. " at " .. t)
    end
  end
end)

test("formats like os.date", function()
  put("/etc/timezone", "Europe/Berlin\n"); clock.forgetZone()
  local t = 1791030896 -- Sat Oct 3 2026, 14:34:56 CEST
  eq(clock.date("%a %A %b %B %d %e %j %y %I %p %Z %F %T %%", t),
     hostDate("Europe/Berlin", t, "%a %A %b %B %d %e %j %y %I %p %Z %F %T %%"))
  eq(clock.date("%T", t, true), "12:34:56", "utc")
end)

test("unknown zone falls back to UTC; no sync means world time", function()
  put("/etc/timezone", "Mars/Olympus\n"); clock.forgetZone()
  eq(clock.zone(0), "UTC")
  local _, real = clock.now()
  eq(real, false)
  has(clock.date("%Z"), "world")
end)

test("date, timedatectl and timesyncd", function()
  users()
  put("/etc/timezone", "UTC\n"); clock.forgetZone()
  has(run("date"), "world", "no sync yet: world time")
  has(run("timedatectl"), "System clock synchronized: no")
  has(run("timedatectl set-timezone Mars/Olympus"), "unknown time zone")
  run("timedatectl set-timezone Asia/Tokyo")
  eq(file("/etc/timezone"), "Asia/Tokyo\n")
  as("bob", function() has(run("timedatectl set-timezone UTC"), "need to be root") end)
  has(run("timedatectl list-timezones"), "Europe/Berlin")
  has(run("timedatectl sync"), "no internet card")
  ok(file("/etc/systemd/system/timesyncd.service"), "unit shipped")
  has(file("/etc/systemd/enabled"), "timesyncd\n", "enabled by default")
end)

test("the time zone is read once a minute, timedatectl applies it at once", function()
  put("/etc/timezone", "UTC\n"); clock.forgetZone()
  eq(clock.zone(0), "UTC")
  put("/etc/timezone", "Asia/Tokyo\n")
  eq(clock.zone(0), "UTC", "a hand edit waits for the next minute")
  run("timedatectl set-timezone Europe/Berlin")
  eq(clock.zone(0), "Europe/Berlin", "timedatectl takes effect right away")
end)
