--[[
  date [-u] [+FORMAT] - the date and time

  Real time in your time zone (/etc/timezone, see timedatectl) once
  timesyncd has synchronized with the internet; without an internet card
  it is the Minecraft world's time, and the zone shows "world".

    -u        in UTC
    +FORMAT   e.g. date +%H:%M or date "+%A, %d %B %Y"
              %Y %m %d %H %M %S %a %A %b %B %e %j %y %I %p %Z %z %F %T %s
]]--
local clock = require("clock")
local utc, fmt = false, nil
for _, a in ipairs(arg or {}) do
  if a == "-u" then utc = true
  elseif a:sub(1, 1) == "+" then fmt = a:sub(2)
  else term.write("usage: date [-u] [+FORMAT]\n"); return 1 end
end
term.write(clock.date(fmt, nil, utc) .. "\n")
return 0
