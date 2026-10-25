--[[
  netfsd - shares folders with other computers (a service)

  The folders are listed in /etc/netfs.conf, each as ro (read only) or rw.
  Other computers mount them with netfs. Paths are kept inside the share:
  neither .. nor a symbolic link leads out of it, and /etc/shadow is never
  shared.
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

local function under(p, dir) return dir == "/" or p == dir or p:sub(1, #dir + 1) == dir .. "/" end
-- every link in p followed (ByteOS 1.17 and later have links)
local function real(p) if fs.realpath then return fs.realpath(p) end return p end

-- the real path of `path` inside the share, and whether it is the share
-- itself; an error when it would lead out of it. \ counts as / (the
-- kernel treats it so). With keepLast a link at the end is not followed
-- (remove and rename act on the link itself).
local function inside(share, path, keepLast)
  local parts = {}
  for part in tostring(path):gmatch("[^/\\]+") do
    if part == ".." then table.remove(parts)
    elseif part ~= "." then parts[#parts + 1] = part end
  end
  local base = real(share.dir) or share.dir
  local p
  if keepLast and #parts > 0 then
    local last = table.remove(parts)
    local dir = real(share.dir .. "/" .. table.concat(parts, "/"))
    p = dir and (dir .. "/" .. last):gsub("/+", "/") or nil
  else
    p = real((share.dir .. "/" .. table.concat(parts, "/"):gsub("/+", "/")))
  end
  -- even a share of / keeps the passwords
  if not p or not under(p, base) or p == "/etc/shadow" then error("outside the share", 0) end
  return p, p == base
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
  local p, top = inside(s, path, true)
  if top then return false, "the share itself cannot be removed" end
  if not fs.exists(p) then return false, "no such file" end
  return fs.remove(p) and true or false, "cannot remove " .. tostring(path)
end
function writes.rename(s, a, b)
  local ok, err = fs.rename(inside(s, a, true), inside(s, b, true))
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
  elseif ops[op] or writes[op] then
    if writes[op] and s.mode ~= "rw" then reply = { false, "read-only share" }
    else
      reply = table.pack(pcall(ops[op] or writes[op], s, ...))
      if not reply[1] then reply = { false, tostring(reply[2]) } else table.remove(reply, 1) end
    end
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
