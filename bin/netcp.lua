--[[
  netcp <file> <host> - send a file to another computer

  It arrives there in /tmp/incoming/<you>@<your host>-<name>, and the
  other screen says so. Files of up to 64 KiB.
]]--
local net = require("net")
local args = arg or {}
if #args ~= 2 then term.write("usage: netcp <file> <host>\n"); return 2 end
local path = shell.normalize(args[1])
local data, rerr = fs.readAll(path)
if not data or fs.isDirectory(path) then term.write("netcp: " .. args[1] .. ": " .. tostring(rerr or "is a directory") .. "\n"); return 1 end
local addr, err = net.resolve(args[2])
if not addr then term.write("netcp: " .. tostring(err) .. "\n"); return 1 end
local c = net.card()
local chunk = math.max(512, (c.maxPacketSize and c.maxPacketSize() or 8192) - 512)
local id = net.newId()
local who = k.user() .. "@" .. tostring(_G.HOSTNAME)
net.send(addr, "file-offer", id, path:match("[^/]+$"), #data, who)
local from, _, accepted, why = net.wait("file-offer-reply", id, 3, addr)
if not from then term.write("netcp: " .. args[2] .. " did not answer\n"); return 1 end
if not accepted then term.write("netcp: refused: " .. tostring(why) .. "\n"); return 1 end
local parts = math.max(1, math.ceil(#data / chunk))
for i = 1, parts do
  net.send(addr, "file-chunk", id, i, data:sub((i - 1) * chunk + 1, i * chunk))
  if not net.wait("file-chunk-reply", id, 3, addr) then term.write("netcp: the transfer stalled\n"); return 1 end
  term.write(("\r  %d%%"):format(math.floor(100 * i / parts)))
end
net.send(addr, "file-done", id)
local done, _, ok, where = net.wait("file-done-reply", id, 3, addr)
term.write("\n")
if not done or not ok then term.write("netcp: failed: " .. tostring(where or "no answer") .. "\n"); return 1 end
term.write("sent; on " .. args[2] .. " it is " .. tostring(where) .. "\n")
return 0
