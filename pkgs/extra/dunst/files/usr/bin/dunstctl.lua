--[[
  dunstctl - control dunst

    dunstctl close             close the newest pop-up
    dunstctl close-all         close them all
    dunstctl history           the last notifications
    dunstctl set-paused true|false|toggle
                               do not disturb: hold back all but critical
    dunstctl is-paused
    dunstctl count             shown, waiting and in the history
]]--
local notify = require("notify")
local d = package.loaded["dunst.state"]
local args = arg or {}
local cmd = args[1] or "count"
if cmd == "history" then
  for _, n in ipairs(notify.history) do
    term.write(("%s%s: %s%s\n"):format(n.app ~= "" and ("[" .. n.app .. "] ") or "", n.summary,
      n.body, n.urgency == "critical" and " (critical)" or ""))
  end
  return 0
end
if not d then term.write("dunstctl: dunst is not running\n"); return 1 end
if cmd == "close" then d.close()
elseif cmd == "close-all" then d.closeAll()
elseif cmd == "set-paused" then
  local v = args[2]
  if v == "toggle" then d.setPaused(not d.paused) else d.setPaused(v == "true") end
elseif cmd == "is-paused" then term.write(tostring(d.paused) .. "\n")
elseif cmd == "count" then
  term.write(("shown %d, waiting %d, history %d\n"):format(#d.shown, #d.waiting, #notify.history))
else
  term.write("usage: dunstctl close | close-all | history | set-paused true|false|toggle | is-paused | count\n")
  return 1
end
return 0
