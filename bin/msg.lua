-- msg <host> <text...> - show a message on another computer's screen
local net = require("net")
local args = arg or {}
if #args < 2 then term.write("usage: msg <host> <text...>\n"); return 2 end
local addr, err = net.resolve(args[1])
if not addr then term.write("msg: " .. tostring(err) .. "\n"); return 1 end
local who = k.user() .. "@" .. tostring(_G.HOSTNAME)
local from = net.request(addr, "msg", 3, who, table.concat(args, " ", 2))
if not from then term.write("msg: " .. args[1] .. " did not answer\n"); return 1 end
return 0
