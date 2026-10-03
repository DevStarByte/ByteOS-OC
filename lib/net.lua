--[[
  /lib/net.lua - talking to other computers through a network card

  ByteOS computers speak "ByteNet" on port 4400: every one with a network
  card runs netd, which answers pings and "who is there", shows messages
  and takes files (see man byteos, NETWORK).

    net.card()                    -> the network card, or nil
    net.send(to, kind, id, ...)   -> send to an address (to = nil: everyone)
    net.request(to, kind, timeout, ...) -> from, distance, answer... | nil, "timeout"
    net.discover([timeout])       -> { { address, name, version, distance }, ... }
    net.resolve(host)             -> address, name | nil, reason
                                     (a host name, an address or its start)
]]--

local net = {}

net.PORT = 4400
net.MAGIC = "bytenet"

function net.card()
  local addr = component.list("modem")()
  local c = addr and component.proxy(addr)
  if c and not c.isOpen(net.PORT) then c.open(net.PORT) end
  return c
end

local counter = 0
function net.newId()
  counter = counter + 1
  return ("%s-%d-%d"):format(kernel.user(), math.floor(computer.uptime() * 1000) % 1000000, counter)
end

function net.send(to, kind, id, ...)
  local c = net.card()
  if not c then return nil, "no network card" end
  if to then return c.send(to, net.PORT, net.MAGIC, kind, id, ...) end
  return c.broadcast(net.PORT, net.MAGIC, kind, id, ...)
end

-- Wait for the answer `kind` to request `id` (from `from`, if given).
-- Returns from, distance, the answer's values; or nil, "timeout".
function net.wait(kind, id, timeout, from)
  local deadline = computer.uptime() + (timeout or 3)
  while true do
    local left = deadline - computer.uptime()
    if left <= 0 then return nil, "timeout" end
    local sig = table.pack(kernel.event.pull(left, "modem_message"))
    -- modem_message, card, sender, port, distance, magic, kind, id, ...
    if sig[1] == "modem_message" and sig[4] == net.PORT and sig[6] == net.MAGIC
        and sig[7] == kind and sig[8] == id and (not from or sig[3] == from) then
      return sig[3], sig[5], table.unpack(sig, 9, sig.n)
    end
  end
end

function net.request(to, kind, timeout, ...)
  local id = net.newId()
  local ok, err = net.send(to, kind, id, ...)
  if not ok then return nil, err end
  return net.wait(kind .. "-reply", id, timeout, to)
end

function net.discover(timeout)
  local id = net.newId()
  local ok, err = net.send(nil, "who", id)
  if not ok then return nil, err end
  local found, deadline = {}, computer.uptime() + (timeout or 1.5)
  while true do
    local from, distance, name, version = net.wait("who-reply", id, deadline - computer.uptime())
    if not from then break end
    found[#found + 1] = { address = from, distance = distance, name = name, version = version }
  end
  table.sort(found, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return found
end

function net.resolve(host)
  if host:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then return host end
  local hosts, err = net.discover()
  if not hosts then return nil, err end
  for _, h in ipairs(hosts) do
    if h.name == host then return h.address, h.name end
  end
  for _, h in ipairs(hosts) do
    if h.address:sub(1, #host) == host then return h.address, h.name end
  end
  return nil, "unknown host '" .. host .. "' (see netscan)"
end

return net
