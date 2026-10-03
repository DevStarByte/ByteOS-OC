--[[
  timerd - starts services when their timers say so (a service)

  Every few seconds it looks at the enabled .timer units and starts the
  services that are due. See man systemd.timer and the timers command.
]]--
local timers = require("timers")
print("watching the timers")
while true do
  local ok, err = pcall(timers.tick, print)
  if not ok then print("error: " .. tostring(err)) end
  k.event.pull(5)
end
