--[[
  /lib/compress.lua  -  pure-Lua LZW compressor with base64 output

  Designed for the ByteOS package format. Output is plain ASCII so it can be
  embedded inside a Lua source file (= a `.pkg` package) without any
  binary-encoding headaches on OpenComputers' filesystem.

  API:
    compress.encode(s)    -- returns a base64 string
    compress.decode(s)    -- returns the original string
    compress.ratio(s)     -- returns #encoded/#original (handy for tooling)

  Algorithm:
    Standard LZW with 12-bit codes (dictionary up to 4096 entries).
    Codes are bit-packed MSB-first, prefixed with a 4-byte big-endian
    code count, then base64-encoded.
]]--

local M = {}

-- ---- base64 ----------------------------------------------------------------
local B64A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64R = {}
for i = 1, #B64A do B64R[B64A:sub(i, i)] = i - 1 end

local function b64encode(bytes)
  local out, n = {}, #bytes
  local i = 1
  while i <= n do
    local a = bytes[i]     or 0
    local b = bytes[i + 1] or 0
    local c = bytes[i + 2] or 0
    local v = a * 65536 + b * 256 + c
    out[#out + 1] = B64A:sub(math.floor(v / 262144) + 1, math.floor(v / 262144) + 1)
    out[#out + 1] = B64A:sub(math.floor(v / 4096)  % 64 + 1, math.floor(v / 4096)  % 64 + 1)
    if i + 1 <= n then
      out[#out + 1] = B64A:sub(math.floor(v / 64) % 64 + 1, math.floor(v / 64) % 64 + 1)
    else
      out[#out + 1] = "="
    end
    if i + 2 <= n then
      out[#out + 1] = B64A:sub(v % 64 + 1, v % 64 + 1)
    else
      out[#out + 1] = "="
    end
    i = i + 3
  end
  return table.concat(out)
end

local function b64decode(s)
  s = s:gsub("[^A-Za-z0-9+/=]", "")
  local out = {}
  local i = 1
  while i <= #s do
    local c1 = s:sub(i,     i)
    local c2 = s:sub(i + 1, i + 1)
    local c3 = s:sub(i + 2, i + 2)
    local c4 = s:sub(i + 3, i + 3)
    local a = B64R[c1] or 0
    local b = B64R[c2] or 0
    local c = B64R[c3] or 0
    local d = B64R[c4] or 0
    local v = a * 262144 + b * 4096 + c * 64 + d
    out[#out + 1] = math.floor(v / 65536) % 256
    if c3 ~= "=" and c3 ~= "" then out[#out + 1] = math.floor(v / 256) % 256 end
    if c4 ~= "=" and c4 ~= "" then out[#out + 1] = v % 256 end
    i = i + 4
  end
  return out
end

-- ---- bit packing -----------------------------------------------------------
local function packCodes(codes, width)
  local bytes = {}
  local buf, bits = 0, 0
  local p2 = { [0] = 1 }
  for i = 1, 32 do p2[i] = p2[i - 1] * 2 end

  for _, c in ipairs(codes) do
    buf  = buf * p2[width] + c
    bits = bits + width
    while bits >= 8 do
      bits = bits - 8
      bytes[#bytes + 1] = math.floor(buf / p2[bits]) % 256
      buf  = buf % p2[bits]
    end
  end
  if bits > 0 then
    bytes[#bytes + 1] = (buf * p2[8 - bits]) % 256
  end
  return bytes
end

local function unpackCodes(bytes, count, width)
  local codes = {}
  local buf, bits = 0, 0
  local p2 = { [0] = 1 }
  for i = 1, 32 do p2[i] = p2[i - 1] * 2 end
  local mask = p2[width]

  for _, b in ipairs(bytes) do
    buf  = buf * 256 + b
    bits = bits + 8
    while bits >= width and #codes < count do
      bits = bits - width
      codes[#codes + 1] = math.floor(buf / p2[bits]) % mask
      buf  = buf % p2[bits]
    end
    if #codes >= count then break end
  end
  return codes
end

-- ---- LZW -------------------------------------------------------------------
local CODE_BITS = 12
local MAX_CODE  = 4096

function M.encode(s)
  if s == nil or s == "" then return "" end
  local dict = {}
  for i = 0, 255 do dict[string.char(i)] = i end
  local nextCode = 256

  local codes = {}
  local w = ""
  for i = 1, #s do
    local c  = s:sub(i, i)
    local wc = w .. c
    if dict[wc] then
      w = wc
    else
      codes[#codes + 1] = dict[w]
      if nextCode < MAX_CODE then
        dict[wc] = nextCode
        nextCode = nextCode + 1
      end
      w = c
    end
  end
  if w ~= "" then codes[#codes + 1] = dict[w] end

  -- header: 4-byte big-endian count
  local n = #codes
  local out = {
    math.floor(n / 16777216) % 256,
    math.floor(n / 65536)    % 256,
    math.floor(n / 256)      % 256,
    n                         % 256,
  }
  local packed = packCodes(codes, CODE_BITS)
  for i = 1, #packed do out[#out + 1] = packed[i] end
  return b64encode(out)
end

function M.decode(s)
  if s == nil or s == "" then return "" end
  local bytes = b64decode(s)
  if #bytes < 4 then return "" end
  local n = bytes[1] * 16777216 + bytes[2] * 65536 + bytes[3] * 256 + bytes[4]

  local codeBytes = {}
  for i = 5, #bytes do codeBytes[#codeBytes + 1] = bytes[i] end
  local codes = unpackCodes(codeBytes, n, CODE_BITS)

  local dict = {}
  for i = 0, 255 do dict[i] = string.char(i) end
  local nextCode = 256

  local out = {}
  if not codes[1] then return "" end
  local prev = dict[codes[1]]
  out[1] = prev
  for i = 2, #codes do
    local c = codes[i]
    local entry
    if dict[c] then
      entry = dict[c]
    elseif c == nextCode then
      entry = prev .. prev:sub(1, 1)
    else
      return nil, "corrupt LZW stream at code " .. i
    end
    out[#out + 1] = entry
    if nextCode < MAX_CODE then
      dict[nextCode] = prev .. entry:sub(1, 1)
      nextCode = nextCode + 1
    end
    prev = entry
  end
  return table.concat(out)
end

function M.ratio(s)
  if s == nil or s == "" then return 0 end
  return #M.encode(s) / #s
end

return M
