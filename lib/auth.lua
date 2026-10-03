--[[
  /lib/auth.lua - users, groups and password hashes

    /etc/passwd   name:x:uid:gid:gecos:home:shell
    /etc/shadow   name:hash:::::::     only root may read it
    /etc/group    name:x:gid:member,member

  Password hashes look like  $sha256$<rounds>$<salt>$<hex>:  SHA-256 of
  salt .. password, fed back into itself <rounds> times. A plain-text
  password (from before ByteOS 1.4) still matches; check() reports it as
  legacy so the caller can store a hash instead.

  Every function that touches files takes `fio`: either { read = fn(path),
  write = fn(path, data) } or a filesystem table with readAll/writeAll
  such as k.fs. The kernel passes access that may read /etc/shadow.
]]--

local auth = {}

local function read(fio, path) return (fio.read or fio.readAll)(path) end
local function write(fio, path, data) return (fio.write or fio.writeAll)(path, data) end

auth.ROUNDS = 512

-- ---- SHA-256 ---------------------------------------------------------------
local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local M32 = 0xffffffff
local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & M32 end

function auth.sha256(msg)
  local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
              0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
  local bits = #msg * 8
  msg = msg .. "\128" .. string.rep("\0", (55 - #msg) % 64) .. string.pack(">I8", bits)
  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do w[i] = string.unpack(">I4", msg, chunk + i * 4) end
    for i = 16, 63 do
      local a, b = w[i - 15], w[i - 2]
      local s0 = rrot(a, 7) ~ rrot(a, 18) ~ (a >> 3)
      local s1 = rrot(b, 17) ~ rrot(b, 19) ~ (b >> 10)
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & M32
    end
    local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for i = 0, 63 do
      local t1 = (h + (rrot(e, 6) ~ rrot(e, 11) ~ rrot(e, 25)) + ((e & f) ~ (~e & g)) + K[i + 1] + w[i]) & M32
      local t2 = ((rrot(a, 2) ~ rrot(a, 13) ~ rrot(a, 22)) + ((a & b) ~ (a & c) ~ (b & c))) & M32
      h, g, f, e, d, c, b, a = g, f, e, (d + t1) & M32, c, b, a, (t1 + t2) & M32
    end
    H[1], H[2], H[3], H[4] = (H[1] + a) & M32, (H[2] + b) & M32, (H[3] + c) & M32, (H[4] + d) & M32
    H[5], H[6], H[7], H[8] = (H[5] + e) & M32, (H[6] + f) & M32, (H[7] + g) & M32, (H[8] + h) & M32
  end
  return ("%08x"):rep(8):format(table.unpack(H))
end

-- ---- Password hashes -------------------------------------------------------
local SALT = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local seeded = false

local function digest(password, salt, rounds)
  local h = auth.sha256(salt .. password)
  for _ = 2, rounds do h = auth.sha256(h .. salt .. password) end
  return h
end

function auth.hash(password, salt, rounds)
  if not salt then
    if not seeded then
      local t = (computer and computer.uptime and computer.uptime() or os.clock()) * 1e6
      math.randomseed(math.floor((os.time() or 0) + t))
      seeded = true
    end
    local s = {}
    for i = 1, 12 do
      local n = math.random(1, #SALT)
      s[i] = SALT:sub(n, n)
    end
    salt = table.concat(s)
  end
  rounds = rounds or auth.ROUNDS
  return ("$sha256$%d$%s$%s"):format(rounds, salt, digest(password, salt, rounds))
end

-- ok, legacy: legacy is true when `stored` was a plain-text password.
function auth.check(password, stored)
  if type(password) ~= "string" or type(stored) ~= "string" or stored == "" then return false end
  local rounds, salt, hex = stored:match("^%$sha256%$(%d+)%$([^$]*)%$(%x+)$")
  if rounds then return digest(password, salt, tonumber(rounds)) == hex, false end
  if stored:sub(1, 1) == "$" or stored == "!" or stored == "*" then return false end -- locked
  return password == stored, true
end

-- ---- Account files ---------------------------------------------------------
local function lines(text)
  local out = {}
  for l in (text or ""):gmatch("[^\r\n]+") do out[#out + 1] = l end
  return out
end

local function fields(line)
  local out = {}
  for f in (line .. ":"):gmatch("([^:]*):") do out[#out + 1] = f end
  return out
end

function auth.users(fio)
  local out = {}
  for _, l in ipairs(lines(read(fio, "/etc/passwd"))) do
    local f = fields(l)
    if f[1] and f[1] ~= "" then
      out[#out + 1] = { name = f[1], uid = tonumber(f[3]) or 0, gid = tonumber(f[4]) or 0,
                        gecos = f[5] or "", home = f[6] or "/", shell = f[7] or "" }
    end
  end
  return out
end

function auth.user(fio, name)
  for _, u in ipairs(auth.users(fio)) do if u.name == name then return u end end
end

function auth.groups(fio)
  local out = {}
  for _, l in ipairs(lines(read(fio, "/etc/group"))) do
    local f = fields(l)
    if f[1] and f[1] ~= "" then
      local members = {}
      for m in (f[4] or ""):gmatch("[^,%s]+") do members[#members + 1] = m end
      out[#out + 1] = { name = f[1], gid = tonumber(f[3]) or 0, members = members }
    end
  end
  return out
end

-- Group names `user` belongs to: the primary group plus supplementary ones.
function auth.groupsOf(fio, name)
  local u = auth.user(fio, name)
  local out = {}
  for _, g in ipairs(auth.groups(fio)) do
    local member = u and g.gid == u.gid
    for _, m in ipairs(g.members) do if m == name then member = true end end
    if member then out[#out + 1] = g end
  end
  return out
end

function auth.inGroup(fio, name, group)
  for _, g in ipairs(auth.groupsOf(fio, name)) do if g.name == group then return true end end
  return false
end

local function writeLines(fio, path, list)
  return write(fio, path, table.concat(list, "\n") .. (#list > 0 and "\n" or ""))
end

-- Replace the line for `name` in a colon file (or append it); nil removes it.
local function setLine(fio, path, name, newLine)
  local out, found = {}, false
  for _, l in ipairs(lines(read(fio, path))) do
    if fields(l)[1] == name then
      found = true
      if newLine then out[#out + 1] = newLine end
    else
      out[#out + 1] = l
    end
  end
  if not found and newLine then out[#out + 1] = newLine end
  return writeLines(fio, path, out)
end

function auth.storedHash(fio, name)
  for _, l in ipairs(lines(read(fio, "/etc/shadow"))) do
    local f = fields(l)
    if f[1] == name then return f[2] end
  end
end

function auth.setPassword(fio, name, password)
  return setLine(fio, "/etc/shadow", name, name .. ":" .. auth.hash(password) .. ":::::::")
end

function auth.validName(name)
  return type(name) == "string" and name:match("^[a-z_][a-z0-9_-]*$") ~= nil and #name <= 32
end

-- Adds a user (no password yet: the account is locked until passwd).
-- opts: home, shell, gid, groups = { "wheel", ... }. Returns the uid.
function auth.addUser(fio, name, opts)
  opts = opts or {}
  local uid = 1000
  for _, u in ipairs(auth.users(fio)) do
    if u.uid >= uid then uid = u.uid + 1 end
  end
  local home = opts.home or ("/home/" .. name)
  local gid = opts.gid or 100
  setLine(fio, "/etc/passwd", name,
    ("%s:x:%d:%d:%s:%s:%s"):format(name, uid, gid, name, home, opts.shell or "/bin/sh"))
  setLine(fio, "/etc/shadow", name, name .. ":!:::::::")
  for _, g in ipairs(opts.groups or {}) do auth.addToGroup(fio, name, g) end
  return uid
end

local function editMembers(fio, group, fn)
  local out, found = {}, false
  for _, l in ipairs(lines(read(fio, "/etc/group"))) do
    local f = fields(l)
    if f[1] == group then
      found = true
      local members = {}
      for m in (f[4] or ""):gmatch("[^,%s]+") do members[#members + 1] = m end
      members = fn(members)
      l = ("%s:%s:%s:%s"):format(f[1], f[2] or "x", f[3] or "", table.concat(members, ","))
    end
    out[#out + 1] = l
  end
  if not found then return nil, "no such group: " .. group end
  return writeLines(fio, "/etc/group", out)
end

function auth.addToGroup(fio, name, group)
  return editMembers(fio, group, function(m)
    for _, x in ipairs(m) do if x == name then return m end end
    m[#m + 1] = name
    return m
  end)
end

function auth.removeFromGroup(fio, name, group)
  return editMembers(fio, group, function(m)
    local out = {}
    for _, x in ipairs(m) do if x ~= name then out[#out + 1] = x end end
    return out
  end)
end

function auth.delUser(fio, name)
  setLine(fio, "/etc/passwd", name, nil)
  setLine(fio, "/etc/shadow", name, nil)
  for _, g in ipairs(auth.groups(fio)) do auth.removeFromGroup(fio, name, g.name) end
end

return auth
