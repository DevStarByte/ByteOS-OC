--[[
  crond - runs the jobs in the crontabs on time (a service)

  Every minute it reads /etc/crontab and each user's ~/.crontab (see
  `man crontab` and `crontab -e`) and starts the jobs that are due, each
  as its user, in the background. What a job prints goes to the system
  log (journalctl -u crond). @reboot jobs run once when crond starts.

  It goes by the real time once timesyncd has it; without an internet
  card by the world's time, whose minutes pass in under a second.

    systemctl enable --now crond
]]--
local cron = require("cron")
local clock = require("clock")

-- the crontabs are read again only after something on the disks changed
local tabs, gen, warned = nil, nil, {}
local function jobs()
  if gen ~= k.fs.generation() then
    tabs = cron.tabs(warned)
    gen = k.fs.generation()
  end
  return tabs
end

for _, job in ipairs(jobs()) do
  if job.reboot then cron.run(job) end
end
print("crond started")

local last
while true do
  local now, key = cron.now()
  if key ~= last then
    last = key
    for _, job in ipairs(jobs()) do
      if cron.due(job, now) then cron.run(job) end
    end
  end
  -- real time: sleep to the next minute; world time: minutes are short
  local t, real = clock.now()
  k.event.pull(real and (60 - t % 60 + 0.2) or 0.4)
end
