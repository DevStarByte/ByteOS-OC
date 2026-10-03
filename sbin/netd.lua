--[[
  netd - answers other computers on the network (a service)

  On port 4400 (ByteNet) it answers pings and "who is there" with this
  computer's name, shows messages sent with msg on the screen and saves
  files sent with netcp into /tmp/incoming/ (64 KiB at most each). Without
  a network card it waits until one is put in.
]]--
local net = require("net")
local LIMIT = 65536
local transfers = {}

-- Tell whoever sits at the screen: as a notification when a daemon shows
-- them (the libnotify and dunst packages), else on the screen itself.
local function notice(text, summary, body)
  local okN, notify = pcall(require, "notify")
  if okN and notify.running() then
    notify.send(summary or "ByteNet", body or text, { app = "netd" })
    print(text)
    return
  end
  local screen = rawget(_G, "term") -- the real screen, not this service's log
  if screen and screen.cwrite then
    screen.write("\n")
    screen.cwrite(screen.theme.accent, text .. "\n")
  end
  print(text)
end

local handlers = {}
function handlers.ping(from, id) net.send(from, "ping-reply", id) end
function handlers.who(from, id) net.send(from, "who-reply", id, _G.HOSTNAME or "byteos", _G._OSVERSION or "ByteOS") end
function handlers.msg(from, id, who, text)
  notice(("Message from %s: %s"):format(tostring(who), tostring(text)), "Message from " .. tostring(who), tostring(text))
  net.send(from, "msg-reply", id, true)
end
handlers["file-offer"] = function(from, id, name, size, who)
  name = tostring(name):gsub("[^%w%._%-]", "_")
  size = tonumber(size) or 0
  if size > LIMIT then return net.send(from, "file-offer-reply", id, false, "too big (64 KiB at most)") end
  transfers[id] = { from = from, name = name, size = size, who = who, parts = {} }
  net.send(from, "file-offer-reply", id, true)
end
handlers["file-chunk"] = function(from, id, index, data)
  local t = transfers[id]
  if not t or t.from ~= from then return end
  t.parts[tonumber(index)] = data
  net.send(from, "file-chunk-reply", id, index)
end
handlers["file-done"] = function(from, id)
  local t = transfers[id]
  if not t or t.from ~= from then return net.send(from, "file-done-reply", id, false, "unknown transfer") end
  transfers[id] = nil
  local data = table.concat(t.parts)
  if #data ~= t.size then return net.send(from, "file-done-reply", id, false, "incomplete") end
  if not fs.isDirectory("/tmp/incoming") then fs.makeDirectory("/tmp/incoming") end
  local path = ("/tmp/incoming/%s-%s"):format(tostring(t.who):gsub("[^%w%._%-@]", "_"), t.name)
  local ok, err = fs.writeAll(path, data)
  if not ok then return net.send(from, "file-done-reply", id, false, tostring(err)) end
  notice(("File from %s: %s (%d bytes)"):format(tostring(t.who), path, #data), "File from " .. tostring(t.who), ("%s (%d bytes)"):format(path, #data))
  net.send(from, "file-done-reply", id, true, path)
end

while not net.card() do k.event.pull(30, "component_added") end
print("listening on port " .. net.PORT)
while true do
  local sig = table.pack(k.event.pull(math.huge, "modem_message"))
  if sig[4] == net.PORT and sig[6] == net.MAGIC and handlers[sig[7]] then
    local ok, err = pcall(handlers[sig[7]], sig[3], sig[8], table.unpack(sig, 9, sig.n))
    if not ok then print("error handling " .. tostring(sig[7]) .. ": " .. tostring(err)) end
  end
end
