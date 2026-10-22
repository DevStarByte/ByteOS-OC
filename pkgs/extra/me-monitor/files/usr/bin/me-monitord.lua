--[[
  me-monitord - watches the minimums in /etc/me-monitor.conf (the
  me-monitor service; see `man me-monitor`)

  Every `interval` seconds (60) it compares the ME network's items with
  their minimums. An item that runs low is written to the system log
  (journalctl -u me-monitor) and shown as a notification when a daemon
  (dunst) runs; once it is back above its minimum that is logged too.
]]--
local mm = require("memonitor")
local cfg, gen = mm.config(), k.fs.generation()
local alerted = {}   -- what -> true while it is low
print(("me-monitord started: %d minimums, every %ds"):format(#cfg.minimums, cfg.interval))

local function tell(text)
  print(text)
  local ok, notify = pcall(require, "notify")
  if ok and notify.running() then notify.send("ME system", text, { app = "me-monitor" }) end
end

while true do
  if k.fs.generation() ~= gen then cfg, gen = mm.config(), k.fs.generation() end
  local p = mm.find()
  if p then
    local lowNow = {}
    for _, l in ipairs(mm.low(mm.items(p), cfg)) do
      lowNow[l.what] = true
      if not alerted[l.what] then
        alerted[l.what] = true
        tell(("low on %s: %d of %d"):format(l.what, l.have, l.want))
      end
    end
    for what in pairs(alerted) do
      if not lowNow[what] then alerted[what] = nil; print(what .. " is back above its minimum") end
    end
  end
  k.event.pull(cfg.interval)
end
