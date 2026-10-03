--[[
  /lib/clock.lua - the time of day

  OpenComputers' own clock (os.time, os.date) is the Minecraft world's
  time. With an internet card, timesyncd sets the real time here (taken
  from the Date header of an HTTP answer), and the time zone in
  /etc/timezone applies, daylight saving time included. Without a sync the
  clock falls back to the world's time.

    clock.now()            -> seconds since 1970 (UTC), real (true/false)
    clock.date(fmt [, t] [, utc]) -> like os.date: %Y %m %d %H %M %S %a %b %Z ...
    clock.sync()           -> true | nil, reason   (asks the internet)
    clock.zone()           -> name, offset in seconds now, abbreviation
    clock.zones()          -> the time zone names, sorted
    clock.synced()         -> uptime of the last sync, or nil
]]--

local clock = {}

local SERVER = "https://raw.githubusercontent.com/DevStarByte/ByteOS-OC/master/etc/issue"
local base, baseUptime -- epoch at uptime baseUptime, when synced

-- ---- calendar --------------------------------------------------------------
local function daysFromCivil(y, m, d)
  y = m <= 2 and y - 1 or y
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
  return era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy - 719468
end

local function civilFromDays(z)
  z = z + 719468
  local era = (z >= 0 and z or z - 146096) // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp + (mp < 10 and 3 or -9)
  return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
end

local function weekday(days) return (days + 4) % 7 end -- 0 = Sunday

-- day number of the n-th Sunday of a month (n = -1: the last one)
local function sunday(y, m, n)
  if n > 0 then
    local first = daysFromCivil(y, m, 1)
    return first + (7 - weekday(first)) % 7 + (n - 1) * 7
  end
  local last = daysFromCivil(m == 12 and y + 1 or y, m == 12 and 1 or m + 1, 1) - 1
  return last - weekday(last)
end

-- ---- time zones --------------------------------------------------------------
local H = 3600
-- daylight saving rules: start and end as UTC seconds for a year, given the
-- zone's standard offset
local DST = {
  eu = function(y) return sunday(y, 3, -1) * 86400 + H, sunday(y, 10, -1) * 86400 + H end,
  us = function(y, off) return sunday(y, 3, 2) * 86400 + 2 * H - off, sunday(y, 11, 1) * 86400 + 2 * H - off - H end,
  au = function(y, off) return sunday(y, 10, 1) * 86400 + 2 * H - off, sunday(y, 4, 1) * 86400 + 2 * H - off end,
  nz = function(y, off) return sunday(y, 9, -1) * 86400 + 2 * H - off, sunday(y, 4, 1) * 86400 + 2 * H - off end,
}
local ZONES = {
  ["UTC"]                 = { 0, nil, "UTC" },
  ["Europe/London"]       = { 0, "eu", "GMT", "BST" },
  ["Europe/Dublin"]       = { 0, "eu", "GMT", "IST" },
  ["Europe/Lisbon"]       = { 0, "eu", "WET", "WEST" },
  ["Europe/Berlin"]       = { H, "eu", "CET", "CEST" },
  ["Europe/Vienna"]       = { H, "eu", "CET", "CEST" },
  ["Europe/Zurich"]       = { H, "eu", "CET", "CEST" },
  ["Europe/Paris"]        = { H, "eu", "CET", "CEST" },
  ["Europe/Amsterdam"]    = { H, "eu", "CET", "CEST" },
  ["Europe/Brussels"]     = { H, "eu", "CET", "CEST" },
  ["Europe/Rome"]         = { H, "eu", "CET", "CEST" },
  ["Europe/Madrid"]       = { H, "eu", "CET", "CEST" },
  ["Europe/Stockholm"]    = { H, "eu", "CET", "CEST" },
  ["Europe/Warsaw"]       = { H, "eu", "CET", "CEST" },
  ["Europe/Prague"]       = { H, "eu", "CET", "CEST" },
  ["Europe/Helsinki"]     = { 2 * H, "eu", "EET", "EEST" },
  ["Europe/Athens"]       = { 2 * H, "eu", "EET", "EEST" },
  ["Europe/Istanbul"]     = { 3 * H, nil, "+03" },
  ["Europe/Moscow"]       = { 3 * H, nil, "MSK" },
  ["America/New_York"]    = { -5 * H, "us", "EST", "EDT" },
  ["America/Chicago"]     = { -6 * H, "us", "CST", "CDT" },
  ["America/Denver"]      = { -7 * H, "us", "MST", "MDT" },
  ["America/Phoenix"]     = { -7 * H, nil, "MST" },
  ["America/Los_Angeles"] = { -8 * H, "us", "PST", "PDT" },
  ["America/Sao_Paulo"]   = { -3 * H, nil, "-03" },
  ["Asia/Dubai"]          = { 4 * H, nil, "+04" },
  ["Asia/Kolkata"]        = { 5 * H + 1800, nil, "IST" },
  ["Asia/Shanghai"]       = { 8 * H, nil, "CST" },
  ["Asia/Tokyo"]          = { 9 * H, nil, "JST" },
  ["Australia/Sydney"]    = { 10 * H, "au", "AEST", "AEDT" },
  ["Pacific/Auckland"]    = { 12 * H, "nz", "NZST", "NZDT" },
}

function clock.zones()
  local out = {}
  for name in pairs(ZONES) do out[#out + 1] = name end
  table.sort(out)
  return out
end

local function zoneName()
  local fs = rawget(_G, "kernel") and kernel.fs
  local text = fs and fs.readAll("/etc/timezone") or ""
  local name = text:match("^%s*(%S+)")
  return ZONES[name] and name or "UTC"
end

-- name, offset (seconds) and abbreviation at UTC time t
function clock.zone(t)
  local name = zoneName()
  local z = ZONES[name]
  local off, abbr = z[1], z[3]
  if z[2] and t then
    local y = civilFromDays(t // 86400)
    local from, to = DST[z[2]](y, z[1])
    local summer = (from < to) and (t >= from and t < to) or (from > to and (t >= from or t < to))
    if summer then off, abbr = off + H, z[4] end
  end
  return name, off, abbr
end

-- ---- now ----------------------------------------------------------------------
function clock.now()
  if base then return base + math.floor(computer.uptime() - baseUptime), true end
  return math.floor(os.time()), false
end

function clock.synced() return baseUptime end

local MONTHS = { Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6, Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12 }

-- "Sat, 03 Oct 2026 12:34:56 GMT" -> seconds since 1970
function clock.parseHttpDate(s)
  local d, mon, y, hh, mm, ss = tostring(s):match("(%d+) (%a%a%a) (%d%d%d%d) (%d%d):(%d%d):(%d%d)")
  if not d or not MONTHS[mon] then return nil end
  return daysFromCivil(tonumber(y), MONTHS[mon], tonumber(d)) * 86400 + tonumber(hh) * 3600 + tonumber(mm) * 60 + tonumber(ss)
end

function clock.sync()
  local okReq, internet = pcall(require, "internet")
  if not okReq or not internet.available() then return nil, "no internet card" end
  local ok, headers = internet.get(SERVER, function() end)
  if not ok then return nil, tostring(headers) end
  local date
  for key, v in pairs(headers or {}) do
    if key:lower() == "date" then date = type(v) == "table" and v[1] or v end
  end
  local t = date and clock.parseHttpDate(date)
  if not t then return nil, "the server sent no usable Date header" end
  base, baseUptime = t, computer.uptime()
  return true
end

-- ---- formatting -------------------------------------------------------------------
local DAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local MONTHNAMES = { "January", "February", "March", "April", "May", "June", "July",
                     "August", "September", "October", "November", "December" }

-- Like os.date for the local zone (utc = true: for UTC). Without a sync it
-- formats the world's time and %Z says "world".
function clock.date(fmt, t, utc)
  local real
  if t == nil then t, real = clock.now() else real = true end
  fmt = fmt or "%a %b %e %H:%M:%S %Z %Y"
  local off, abbr = 0, "UTC"
  if not real then abbr = "world"
  elseif not utc then off, abbr = select(2, clock.zone(t)) end
  local lt = t + off
  local days = lt // 86400
  local secs = lt % 86400
  local y, m, d = civilFromDays(days)
  local hh, mi, ss = secs // 3600, secs % 3600 // 60, secs % 60
  local wd = weekday(days)
  local yday = days - daysFromCivil(y, 1, 1) + 1
  local function z2(n) return ("%02d"):format(n) end
  local codes = {
    Y = tostring(y), y = z2(y % 100), m = z2(m), d = z2(d), e = ("%2d"):format(d),
    H = z2(hh), M = z2(mi), S = z2(ss), I = z2((hh + 11) % 12 + 1), p = hh < 12 and "AM" or "PM",
    a = DAYS[wd + 1]:sub(1, 3), A = DAYS[wd + 1], b = MONTHNAMES[m]:sub(1, 3), B = MONTHNAMES[m],
    j = ("%03d"):format(yday), Z = abbr, s = tostring(t), ["%"] = "%",
    z = ("%s%02d%02d"):format(off < 0 and "-" or "+", math.abs(off) // 3600, math.abs(off) % 3600 // 60),
  }
  codes.F = codes.Y .. "-" .. codes.m .. "-" .. codes.d
  codes.T = codes.H .. ":" .. codes.M .. ":" .. codes.S
  codes.D = codes.m .. "/" .. codes.d .. "/" .. codes.y
  codes.c = codes.a .. " " .. codes.b .. " " .. codes.e .. " " .. codes.T .. " " .. codes.Y
  return (fmt:gsub("%%(.)", function(c) return codes[c] or ("%" .. c) end))
end

return clock
