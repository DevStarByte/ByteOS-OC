--[[
  /usr/lib/netfs.lua - a shared folder on another computer, as a filesystem

    netfs.shares(host)                 -> { { name, mode }, ... } | nil, reason
    netfs.proxy(address, name, share)  -> a filesystem proxy for kernel.fs.mount
    netfs.mounted()                    -> { { path, host, share }, ... }

  Every call is a request to that computer's netfsd. A file opened for
  writing is sent when it is closed. What a directory listing says is
  remembered for two seconds, so ls does not ask once per file.
]]--
local net = require("net")
local netfs = {}
local CHUNK, TIMEOUT, CACHE = 4096, 5, 2

function netfs.shares(host)
  local addr, name = net.resolve(host)
  if not addr then return nil, name end
  local from, _, list = net.request(addr, "netfs-shares", TIMEOUT)
  if not from then return nil, "no answer from " .. host .. " (does it have netfs?)" end
  local out = {}
  for n, mode in tostring(list):gmatch("(%S+) (%S+)") do out[#out + 1] = { name = n, mode = mode } end
  return out, addr, name or host
end

function netfs.proxy(addr, hostName, share, mode)
  local p = { address = ("netfs-%s-%s"):format(addr:sub(1, 8), share), netfs = { host = hostName, share = share, address = addr } }
  local cache = {}     -- path -> { at, isDir, size }
  local handles, nextH = {}, 1

  local function call(op, ...)
    local from, _, ok, a, b = net.request(addr, "netfs", TIMEOUT, share, op, ...)
    if not from then return nil, hostName .. " does not answer" end
    if not ok then return nil, a end
    return true, a, b
  end
  local function stat(path)
    local c = cache[path]
    if c and computer.uptime() - c.at < CACHE then return c end
    local ok, isDir, size = call("stat", path)
    c = { at = computer.uptime(), exists = ok and isDir ~= nil, isDir = isDir == true, size = tonumber(size) or 0 }
    cache[path] = c
    return c
  end
  local function changed() cache = {} end

  function p.getLabel() return hostName .. ":" .. share end
  function p.isReadOnly() return mode ~= "rw" end
  function p.exists(path) return stat(path).exists end
  function p.isDirectory(path) return stat(path).isDir end
  function p.size(path) return stat(path).size end
  function p.lastModified() return 0 end
  function p.spaceTotal() local _, t = call("space"); return tonumber(t) or 0 end
  function p.spaceUsed() local _, _, u = call("space"); return tonumber(u) or 0 end
  function p.list(path)
    local ok, list = call("list", path)
    if not ok then return nil, list end
    local out, now = {}, computer.uptime()
    local dir = path:gsub("/$", "")
    for name, size in tostring(list):gmatch("([^\n]+)\t(%d+)\n") do
      out[#out + 1] = name
      local isDir = name:sub(-1) == "/"
      cache[dir .. "/" .. name:gsub("/$", "")] = { at = now, exists = true, isDir = isDir, size = tonumber(size) }
    end
    return out
  end
  function p.makeDirectory(path) changed(); return call("mkdir", path) end
  function p.remove(path) changed(); return call("remove", path) end
  function p.rename(a, b) changed(); return call("rename", a, b) end

  function p.open(path, m)
    m = (m or "r"):sub(1, 1)
    if m == "r" then
      local c = stat(path)
      if not c.exists or c.isDir then return nil, path end
    elseif mode ~= "rw" then
      return nil, "read-only share"
    end
    local h = nextH; nextH = nextH + 1
    handles[h] = { path = path, mode = m, pos = 0, out = {} }
    return h
  end
  function p.read(h, n)
    local f = handles[h]
    if not f then return nil, "bad file" end
    n = math.min(n == math.huge and CHUNK or n, CHUNK)
    local ok, data = call("read", f.path, f.pos, n)
    if not ok then return nil, data end
    if not data or data == "" then return nil end
    f.pos = f.pos + #data
    return data
  end
  function p.write(h, data)
    local f = handles[h]
    if not f or f.mode == "r" then return nil, "bad file" end
    f.out[#f.out + 1] = data
    return true
  end
  function p.seek(h, whence, offset)
    local f = handles[h]
    if not f then return nil, "bad file" end
    if whence == "set" then f.pos = offset or 0
    elseif whence == "cur" then f.pos = f.pos + (offset or 0)
    elseif whence == "end" then f.pos = stat(f.path).size + (offset or 0) end
    return f.pos
  end
  function p.close(h)
    local f = handles[h]
    handles[h] = nil
    if not f or f.mode == "r" then return true end
    changed()
    local data = table.concat(f.out)
    local append = f.mode == "a"
    if data == "" and not append then return call("write", f.path, "", false) end
    for i = 1, #data, CHUNK do
      local ok, err = call("write", f.path, data:sub(i, i + CHUNK - 1), append)
      if not ok then return nil, err end
      append = true
    end
    return true
  end
  return p
end

function netfs.mounted()
  local out = {}
  for _, m in ipairs(kernel.fs.mounts()) do
    if type(m.proxy) == "table" and m.proxy.netfs then
      out[#out + 1] = { path = m.path, host = m.proxy.netfs.host, share = m.proxy.netfs.share,
                        mode = m.proxy.isReadOnly() and "ro" or "rw" }
    end
  end
  table.sort(out, function(a, b) return a.path < b.path end)
  return out
end

return netfs
