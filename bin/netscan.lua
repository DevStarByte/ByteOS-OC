-- netscan - the ByteOS computers on the network (that run netd)
local net = require("net")
local T = term.theme
local hosts, err = net.discover(2)
if not hosts then term.write("netscan: " .. tostring(err) .. "\n"); return 1 end
if #hosts == 0 then term.write("no other ByteOS computer answered\n"); return 1 end
term.cwrite(T.bright, ("%-16s %-10s %8s  %s\n"):format("NAME", "ADDRESS", "DISTANCE", "SYSTEM"))
for _, h in ipairs(hosts) do
  term.write(("%-16s %-10s %8s  %s\n"):format(tostring(h.name), h.address:sub(1, 8),
    ("%.0f"):format(tonumber(h.distance) or 0), tostring(h.version)))
end
return 0
