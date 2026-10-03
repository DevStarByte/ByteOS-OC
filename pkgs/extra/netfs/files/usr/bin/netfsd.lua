--[[
  netfsd - shares folders with other computers (a service)

  The folders are listed in /etc/netfs.conf, each as ro (read only) or rw.
  Other computers mount them with netfs. Paths are kept inside the share:
  .. never leads out of it.
]]--
local net = require("net")
local CONF, CHUNK = "/etc/netfs.conf", 4096

local function shares()
  local out = {}
  for line in (fs.readAll(CONF) or ""):gmatch("[^\r\n]+") do
    local name, dir, mode = line:match("^%s*([^#%s]%S*)%s+(%S+)%s*(%S*)")
    if name then out[name] = { dir = dir:gsub("/+$", ""), mode = mode == "rw" and "rw" or "ro" } end
  end
  return out
end

-- the real path of `path` inside the share; nothing above its directory
local function inside(share, path)
  local parts = {}
  for part in tostring(path):gmatch("[^/]+") do
    if part == ".." then table.remove(parts)
    elseif part ~= "." then parts[#parts + 1] = part end
  end
  local real = (share.dir .. "/" .. table.concat(parts, "/")):gsub("/+", "/")
  if real == "/etc/shadow" then real = "/nonexistent" end -- even a share of / keeps passwords
  return real, #parts == 0
end

local ops = {}
function ops.stat(s, path)
  local real = inside(s, path)
  if not fs.exists(real) then return true end
  return true, fs.isDirectory(real), fs.size(real)
end
function ops.list(s, path)
  local real = inside(s, path)
  if not fs.isDirectory(real) then return false, "not a directory" end
  local out = {}
  for _, name in ipairs(fs.list(real) or {}) do
    local size = name:sub(-1) == "/" and 0 or fs.size(real .. "/" .. name)
    out[#out + 1] = name .. "\t" .. math.floor(size) .. "\n"
  end
  return true, table.concat(out)
end
function ops.read(s, path, offset, n)
  local f, err = fs.open(inside(s, path), "r")
  if not f then return false, err end
  if (tonumber(offset) or 0) > 0 then f:seek("set", math.floor(offset)) end
  local data = f:read(math.min(tonumber(n) or CHUNK, CHUNK))
  f:close()
  return true, data or ""
end
function ops.space(s)
  local p = fs.resolve(s.dir)
  return true, p and p.spaceTotal() or 0, p and p.spaceUsed() or 0
end
local writes = {}
function writes.write(s, path, data, append)
  local f, err = fs.open(inside(s, path), append and "a" or "w")
  if not f then return false, err end
  f:write(tostring(data or "")); f:close()
  return true
end
function writes.mkdir(s, path) return fs.makeDirectory(inside(s, path)) and true or false, "cannot create " .. tostring(path) end
function writes.remove(s, path)
  local real, top = inside(s, path)
  if top then return false, "the share itself cannot be removed" end
  if not fs.exists(real) then return false, "no such file" end
  return fs.remove(real) and true or false, "cannot remove " .. tostring(path)
end
function writes.rename(s, a, b)
  local ok, err = fs.rename(inside(s, a), inside(s, b))
  return ok and true or false, err
end

local function handle(from, kind, id, name, op, ...)
  if kind == "netfs-shares" then
    local list = {}
    for n, s in pairs(shares()) do list[#list + 1] = n .. " " .. s.mode end
    table.sort(list)
    return net.send(from, "netfs-shares-reply", id, table.concat(list, "\n"))
  end
  local s = shares()[tostring(name)]
  local reply
  if not s then reply = { false, "no share " .. tostring(name) }
  elseif ops[op] then reply = { ops[op](s, ...) }
  elseif writes[op] then
    if s.mode ~= "rw" then reply = { false, "read-only share" } else reply = { writes[op](s, ...) } end
  else reply = { false, "unknown operation " .. tostring(op) } end
  net.send(from, "netfs-reply", id, table.unpack(reply))
end

while not net.card() do k.event.pull(30, "component_added") end
print("sharing the folders in " .. CONF)
while true do
  local sig = table.pack(k.event.pull(math.huge, "modem_message"))
  if sig[4] == net.PORT and sig[6] == net.MAGIC and (sig[7] == "netfs" or sig[7] == "netfs-shares") then
    local ok, err = pcall(handle, sig[3], sig[7], sig[8], table.unpack(sig, 9, sig.n))
    if not ok then
      print("error: " .. tostring(err))
      net.send(sig[3], sig[7] .. "-reply", sig[8], false, "server error")
    end
  end
end
