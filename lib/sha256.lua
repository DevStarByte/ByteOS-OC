--[[
  /lib/sha256.lua - SHA-256

    sha256.hex(data) -> 64 hex digits

  Pure Lua 5.3+, so it also runs on a PC (tools/mkrepo.lua). Inside
  OpenComputers a data card, when there is one, does the work instead.
]]--

local sha256 = {}

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

-- SHA-256 of msg in pure Lua, as 64 hex digits.
local function pure(msg)
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

local function card()
  local c = rawget(_G, "component")
  if not c or not c.list then return nil end
  local addr = c.list("data")()
  return addr and c.proxy(addr)
end

function sha256.hex(data)
  local dc = card()
  if dc and dc.sha256 then
    local ok, raw = pcall(dc.sha256, data)
    if ok and type(raw) == "string" and #raw == 32 then
      return (raw:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
    end
  end
  return pure(data)
end

return sha256
