--[[
  notify-send [-u low|normal|critical] [-t seconds] [-a app] <summary> [body]

  Shows a notification (a daemon such as dunst must run):
    notify-send "Backup done" "42 files saved"
    notify-send -u critical "Reactor" "too hot!"
  -t 0 keeps it until it is clicked away.
]]--
local notify = require("notify")
local args = arg or {}
local opts, rest = {}, {}
local i = 1
while args[i] do
  local a = args[i]
  if a == "-u" or a == "--urgency" then opts.urgency = args[i + 1]; i = i + 1
  elseif a == "-t" or a == "--expire-time" then opts.timeout = tonumber(args[i + 1]); i = i + 1
  elseif a == "-a" or a == "--app-name" then opts.app = args[i + 1]; i = i + 1
  else rest[#rest + 1] = a end
  i = i + 1
end
if opts.urgency and opts.urgency ~= "low" and opts.urgency ~= "normal" and opts.urgency ~= "critical" then
  term.write("notify-send: urgency is low, normal or critical\n"); return 1
end
if not rest[1] then term.write("usage: notify-send [-u urgency] [-t seconds] [-a app] <summary> [body]\n"); return 1 end
local id, err = notify.send(rest[1], table.concat(rest, " ", 2), opts)
if not id then term.write("notify-send: " .. err .. "\n"); return 1 end
return 0
