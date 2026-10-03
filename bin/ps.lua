-- ps - the running processes: init (pid 1) and every background job/service
local T = term.theme
local now = computer.uptime()
term.cwrite(T.bright, ("%5s %-8s %-8s %8s  %s\n"):format("PID", "USER", "STATE", "TIME", "COMMAND"))
for _, p in ipairs(k.process.list()) do
  local secs = math.floor(now - (p.started or 0))
  local time = ("%d:%02d"):format(secs // 60, secs % 60)
  term.write(("%5d %-8s %-8s %8s  %s\n"):format(p.pid, p.user, p.state, time, p.name))
end
return 0
