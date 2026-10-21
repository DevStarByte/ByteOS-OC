--[[
  uptime [-p] [-s] - how long the computer has been running

    uptime      12:34:56 up 2:05,  1 user,  4 processes
    uptime -p   up 2 hours, 5 minutes
    uptime -s   when it started: 2026-10-21 10:29:51

  The time of day is the real time once timesyncd has synchronized (see
  date), else the Minecraft world's.
]]--
local clock = require("clock")
local pretty, since = false, false
for _, a in ipairs(arg or {}) do
  if a == "-p" or a == "--pretty" then pretty = true
  elseif a == "-s" or a == "--since" then since = true
  else term.write("usage: uptime [-p] [-s]\n"); return 1 end
end

local up = math.floor(computer.uptime())
if since then
  local now = clock.now()
  term.write(clock.date("%F %T", now - up) .. "\n")
  return 0
end

local d, h, m = up // 86400, up % 86400 // 3600, up % 3600 // 60
local function plural(n, word, many) return n .. " " .. (n == 1 and word or many or word .. "s") end
if pretty then
  local parts = {}
  if d > 0 then parts[#parts + 1] = plural(d, "day") end
  if h > 0 then parts[#parts + 1] = plural(h, "hour") end
  if m > 0 or #parts == 0 then parts[#parts + 1] = plural(m, "minute") end
  term.write("up " .. table.concat(parts, ", ") .. "\n")
  return 0
end

local span = (d > 0 and plural(d, "day") .. ", " or "") .. (h > 0 and ("%d:%02d"):format(h, m) or (m .. " min"))
local users, procs = { [k.user()] = true }, k.process.list()
-- services run as root; other users are people logged in (or their jobs)
for _, p in ipairs(procs) do if p.user ~= "root" then users[p.user] = true end end
local nUsers = 0
for _ in pairs(users) do nUsers = nUsers + 1 end
term.write(("%s up %s,  %s,  %s\n"):format(clock.date("%H:%M:%S"), span, plural(nUsers, "user"),
  plural(#procs, "process", "processes")))
return 0
