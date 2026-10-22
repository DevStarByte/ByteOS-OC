--[[
  reactorctld - controls the reactors automatically (the reactorctl
  service; see `man reactorctl`)

  Every `interval` seconds it puts each reactor's control rods in as far
  as its energy buffer is full, stops it above off_above % and starts it
  below on_below %. What it changes goes to the system log
  (journalctl -u reactorctl). /etc/reactorctl.conf is read again when it
  changes. Actively cooled reactors (steam for turbines) are left alone.
]]--
local rc = require("reactorctl")
local cfg, gen = rc.config(), k.fs.generation()
print(("reactorctld started: rods follow the buffer, off above %d%%, on below %d%%")
  :format(cfg.off_above, cfg.on_below))
while true do
  if k.fs.generation() ~= gen then cfg, gen = rc.config(), k.fs.generation() end
  rc.step(cfg, print)
  k.event.pull(cfg.interval)
end
