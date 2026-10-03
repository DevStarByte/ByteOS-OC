-- sleep N[s|m|h] - wait N seconds (or minutes/hours); Ctrl+C ends it
local a = (arg or {})[1]
local n, unit = tostring(a or ""):match("^(%d*%.?%d+)([smh]?)$")
if not n then term.write("usage: sleep N[s|m|h]\n"); return 1 end
local seconds = tonumber(n) * ({ s = 1, m = 60, h = 3600 })[unit ~= "" and unit or "s"]
local deadline = computer.uptime() + seconds
while computer.uptime() < deadline do
  k.event.pull(deadline - computer.uptime())
end
return 0
