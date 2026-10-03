--[[
  ping [-c count] <host> - is another computer there, and how fast it answers

  host is a name (see netscan), an address or its first characters.
  Stops after count answers (default 4); Ctrl+C stops it earlier.
]]--
local net = require("net")
local args = arg or {}
local count, host = 4, nil
local i = 1
while i <= #args do
  if args[i] == "-c" then i = i + 1; count = tonumber(args[i]) or count else host = args[i] end
  i = i + 1
end
if not host then term.write("usage: ping [-c count] <host>\n"); return 2 end
local addr, name = net.resolve(host)
if not addr then term.write("ping: " .. tostring(name) .. "\n"); return 2 end
name = name or addr:sub(1, 8)
term.write(("PING %s (%s)\n"):format(name, addr:sub(1, 8)))
local got = 0
for n = 1, count do
  local t0 = computer.uptime()
  local from, distance = net.request(addr, "ping", 2)
  if from then
    got = got + 1
    term.write(("reply from %s: seq=%d time=%.0f ms distance=%.0f\n"):format(name, n,
      (computer.uptime() - t0) * 1000, tonumber(distance) or 0))
  else
    term.write(("no reply: seq=%d\n"):format(n))
  end
  if n < count then k.event.pull(1, "__ping_pause__") end
end
term.write(("%d sent, %d answered, %d%% lost\n"):format(count, got, math.floor(100 * (count - got) / count + 0.5)))
return got > 0 and 0 or 1
