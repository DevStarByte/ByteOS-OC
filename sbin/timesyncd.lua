--[[
  timesyncd - keeps the clock on real time (a service, see timedatectl)

  At start and then every hour it asks the internet for the time; after a
  failure it tries again in a minute. It logs only when something changes,
  so a computer without an internet card does not fill the log.
]]--
local clock = require("clock")
local said
while true do
  local ok, err = clock.sync()
  local msg = ok and "clock synchronized" or ("cannot synchronize the clock: " .. tostring(err))
  if msg ~= said or ok then
    print(ok and ("Synchronized: " .. clock.date("%a %F %T %Z")) or msg)
    said = msg
  end
  k.event.pull(ok and 3600 or 60)
end
