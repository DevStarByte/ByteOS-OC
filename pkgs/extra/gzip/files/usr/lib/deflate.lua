--[[
  /usr/lib/deflate.lua - DEFLATE and gzip (RFC 1951, 1952) in plain Lua

    local deflate = require("deflate")
    deflate.crc32(s [, crc])               -> CRC-32 of s (continuing crc)
    deflate.gzipStream(sink [, opts])      -> { write = fn(data), finish = fn() }
        gzip what is written, handing the result to sink(piece);
        opts.level 1-9 (6), opts.name, opts.mtime, opts.breathe
    deflate.gunzip(src, sink [, breathe])  -> true | nil, reason
        src() returns the next piece of the .gz data (nil at the end),
        sink(piece) gets what it unpacks; several members in a row work
    deflate.isGzip(s)                      -> true if s starts like a .gz

  Memory stays small whatever the size: unpacking keeps the last 32 KiB
  plus a few KiB being built, packing a 32 KiB window and a fixed hash
  table (its size grows with the level). Packing uses LZ77 with the
  fixed Huffman codes, so the result is a bit bigger than a PC's gzip
  makes, but any gzip opens it. breathe() is called now and then on long
  work (OpenComputers stops a computer that never waits).
]]--

local deflate = {}

-- ---- CRC-32 --------------------------------------------------------------------
local CRC = {}
for n = 0, 255 do
  local c = n
  for _ = 1, 8 do c = (c & 1 ~= 0) and (0xEDB88320 ~ (c >> 1)) or (c >> 1) end
  CRC[n] = c
end

function deflate.crc32(s, crc)
  crc = (crc or 0) ~ 0xFFFFFFFF
  local byte = string.byte
  for i = 1, #s do crc = CRC[(crc ~ byte(s, i)) & 0xFF] ~ (crc >> 8) end
  return crc ~ 0xFFFFFFFF
end

function deflate.isGzip(s) return s:sub(1, 2) == "\31\139" end

-- ---- the tables of RFC 1951 ----------------------------------------------------------
local LBASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
  67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
  1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DEXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
  12, 12, 13, 13 }
local CLORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local function breather(fn)
  if not fn then return function() end end
  local last = computer.uptime()
  return function()
    local now = computer.uptime()
    if now - last > 0.5 then last = now; fn() end
  end
end

-- ---- unpacking -------------------------------------------------------------------------
-- Bits from src's pieces, least significant first.
local function bitReader(src)
  local s, pos, bitbuf, bitcnt = "", 1, 0, 0
  local r = {}
  local function more()
    while pos > #s do
      local c = src()
      if not c then return false end
      s, pos = c, 1
    end
    return true
  end
  function r.bits(n)
    while bitcnt < n do
      if not more() then error("unexpected end of the compressed data", 0) end
      bitbuf = bitbuf | (s:byte(pos) << bitcnt)
      pos, bitcnt = pos + 1, bitcnt + 8
    end
    local v = bitbuf & ((1 << n) - 1)
    bitbuf, bitcnt = bitbuf >> n, bitcnt - n
    return v
  end
  function r.align() local drop = bitcnt % 8; bitbuf, bitcnt = bitbuf >> drop, bitcnt - drop end
  function r.atEnd() return bitcnt == 0 and not more() end
  return r
end

-- A Huffman code from code lengths (canonical, as zlib's puff): counts per
-- length and the symbols in code order.
local function huffman(lengths, n)
  local counts, offs, symbols = {}, {}, {}
  for l = 0, 15 do counts[l] = 0 end
  for sym = 0, n - 1 do counts[lengths[sym] or 0] = counts[lengths[sym] or 0] + 1 end
  offs[1] = 0
  for l = 1, 14 do offs[l + 1] = offs[l] + counts[l] end
  for sym = 0, n - 1 do
    local l = lengths[sym] or 0
    if l ~= 0 then symbols[offs[l]] = sym; offs[l] = offs[l] + 1 end
  end
  return { counts = counts, symbols = symbols }
end

local function decodeSym(br, h)
  local code, first, index = 0, 0, 0
  local counts = h.counts
  for len = 1, 15 do
    code = code | br.bits(1)
    local count = counts[len]
    if code - count < first then return h.symbols[index + code - first] end
    index, first = index + count, (first + count) << 1
    code = code << 1
  end
  error("corrupt compressed data (bad Huffman code)", 0)
end

local FIXED_L, FIXED_D
local function fixedCodes()
  if not FIXED_L then
    local l = {}
    for i = 0, 143 do l[i] = 8 end
    for i = 144, 255 do l[i] = 9 end
    for i = 256, 279 do l[i] = 7 end
    for i = 280, 287 do l[i] = 8 end
    FIXED_L = huffman(l, 288)
    local d = {}
    for i = 0, 29 do d[i] = 5 end
    FIXED_D = huffman(d, 30)
  end
  return FIXED_L, FIXED_D
end

-- Output with the 32 KiB window: `win` holds what came before, `seg` the
-- bytes of the piece being built (as one-character strings).
local SEG = 4096
local function window(sink)
  local w = { win = "", seg = {}, n = 0 }
  function w.flush()
    if w.n == 0 then return end
    local piece = table.concat(w.seg, "", 1, w.n)
    sink(piece)
    local all = w.win .. piece
    w.win = #all > 32768 and all:sub(-32768) or all
    w.seg, w.n = {}, 0
  end
  function w.put(ch)
    w.n = w.n + 1; w.seg[w.n] = ch
    if w.n >= SEG then w.flush() end
  end
  function w.copy(len, dist)
    if dist > #w.win + w.n then error("corrupt compressed data (distance too far back)", 0) end
    for _ = 1, len do
      local ch
      if dist <= w.n then ch = w.seg[w.n - dist + 1]
      else
        local at = #w.win - (dist - w.n) + 1
        ch = w.win:sub(at, at)
      end
      w.put(ch)
    end
  end
  return w
end

local function inflateBlocks(br, w, breathe)
  local char = string.char
  repeat
    local final = br.bits(1)
    local kind = br.bits(2)
    if kind == 0 then
      br.align()
      local len, nlen = br.bits(16), br.bits(16)
      if len ~= (~nlen & 0xFFFF) then error("corrupt compressed data (stored block length)", 0) end
      for _ = 1, len do w.put(char(br.bits(8))) end
    elseif kind == 1 or kind == 2 then
      local lit, dst
      if kind == 1 then lit, dst = fixedCodes()
      else
        local hlit, hdist, hclen = br.bits(5) + 257, br.bits(5) + 1, br.bits(4) + 4
        local cl = {}
        for i = 1, hclen do cl[CLORDER[i]] = br.bits(3) end
        local clh = huffman(cl, 19)
        local lens, i = {}, 0
        while i < hlit + hdist do
          local sym = decodeSym(br, clh)
          if sym < 16 then lens[i] = sym; i = i + 1
          else
            local rep, val = 0, 0
            if sym == 16 then
              if i == 0 then error("corrupt compressed data (repeat with nothing before)", 0) end
              val, rep = lens[i - 1], 3 + br.bits(2)
            elseif sym == 17 then rep = 3 + br.bits(3)
            else rep = 11 + br.bits(7) end
            for _ = 1, rep do lens[i] = val; i = i + 1 end
          end
        end
        local ll, dl = {}, {}
        for j = 0, hlit - 1 do ll[j] = lens[j] end
        for j = 0, hdist - 1 do dl[j] = lens[hlit + j] end
        lit, dst = huffman(ll, hlit), huffman(dl, hdist)
      end
      while true do
        local sym = decodeSym(br, lit)
        if sym < 256 then w.put(char(sym))
        elseif sym == 256 then break
        else
          sym = sym - 256
          if sym > 29 then error("corrupt compressed data (bad length)", 0) end
          local len = LBASE[sym] + br.bits(LEXTRA[sym])
          local d = decodeSym(br, dst) + 1
          if d > 30 then error("corrupt compressed data (bad distance)", 0) end
          w.copy(len, DBASE[d] + br.bits(DEXTRA[d]))
        end
        breathe()
      end
    else
      error("corrupt compressed data (block type 3)", 0)
    end
  until final == 1
end

function deflate.gunzip(src, sink, breathe)
  breathe = breather(breathe)
  local ok, err = pcall(function()
    local br = bitReader(src)
    local members = 0
    repeat
      local b1, b2 = br.bits(8), br.bits(8)
      if b1 ~= 31 or b2 ~= 139 then
        if members > 0 then return end -- trailing garbage after a member, as gzip allows
        error("not in gzip format", 0)
      end
      if br.bits(8) ~= 8 then error("unknown compression method", 0) end
      local flags = br.bits(8)
      for _ = 1, 6 do br.bits(8) end -- mtime, extra flags, OS
      if flags & 4 ~= 0 then for _ = 1, br.bits(16) do br.bits(8) end end -- FEXTRA
      if flags & 8 ~= 0 then repeat until br.bits(8) == 0 end            -- FNAME
      if flags & 16 ~= 0 then repeat until br.bits(8) == 0 end           -- FCOMMENT
      if flags & 2 ~= 0 then br.bits(16) end                              -- FHCRC
      local crc, size = 0, 0
      local w = window(function(piece)
        crc = deflate.crc32(piece, crc); size = size + #piece
        sink(piece)
      end)
      inflateBlocks(br, w, breathe)
      w.flush()
      br.align()
      local want = br.bits(16) | (br.bits(16) << 16)
      local wantSize = br.bits(16) | (br.bits(16) << 16)
      if want ~= crc then error("CRC error: the data is damaged", 0) end
      if wantSize ~= size & 0xFFFFFFFF then error("length error: the data is damaged", 0) end
      members = members + 1
    until br.atEnd()
  end)
  if not ok then return nil, err end
  return true
end

-- ---- packing ---------------------------------------------------------------------------
-- Fixed Huffman codes, bit-reversed so they can be written LSB first.
local function reverse(code, len)
  local r = 0
  for _ = 1, len do r = (r << 1) | (code & 1); code = code >> 1 end
  return r
end
local LCODE, LLEN, DCODE
local function fixedOut()
  if LCODE then return end
  LCODE, LLEN, DCODE = {}, {}, {}
  for s = 0, 287 do
    local code, len
    if s <= 143 then code, len = 0x30 + s, 8
    elseif s <= 255 then code, len = 0x190 + s - 144, 9
    elseif s <= 279 then code, len = s - 256, 7
    else code, len = 0xC0 + s - 280, 8 end
    LCODE[s], LLEN[s] = reverse(code, len), len
  end
  for d = 0, 29 do DCODE[d] = reverse(d, 5) end
end

-- length 3..258 -> code index (1-based into LBASE), distance 1..32768 -> index
local function lengthIndex(len)
  local i = 29
  while LBASE[i] > len do i = i - 1 end
  return i
end
local function distIndex(d)
  local lo, hi = 1, 30
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if DBASE[mid] <= d then lo = mid else hi = mid - 1 end
  end
  return lo
end

local BLOCK = 8192   -- bytes of input packed at a time
local WINDOW = 32768

-- A raw DEFLATE stream: write(data) as often as wanted, then finish().
local function compressor(sink, level, breathe)
  fixedOut()
  level = level or 6
  local buckets = level <= 3 and 1024 or level <= 6 and 4096 or 16384
  local longest = level <= 3 and 32 or 258   -- low levels stop matches early: faster
  local head = {}
  for i = 1, buckets do head[i] = 0 end
  local hist, histStart = "", 1     -- the window: absolute position of hist's first byte
  local pending = ""                 -- input not packed yet
  local bitbuf, bitcnt, out = 0, 0, {}
  local function put(v, n)
    bitbuf = bitbuf | (v << bitcnt); bitcnt = bitcnt + n
    while bitcnt >= 8 do
      out[#out + 1] = string.char(bitbuf & 0xFF)
      bitbuf, bitcnt = bitbuf >> 8, bitcnt - 8
    end
  end
  local function flushOut()
    if #out > 0 then sink(table.concat(out)); out = {} end
  end

  local function block(data, final)
    local saveBuf, saveCnt, saveN = bitbuf, bitcnt, #out
    put(final and 1 or 0, 1); put(1, 2) -- fixed Huffman
    local base = histStart + #hist    -- absolute position of data's first byte
    local all = hist .. data
    local off = histStart - 1         -- all:byte(p - off) is absolute position p
    local byte = string.byte
    local n, i = #data, 0
    while i < n do
      local p = base + i
      local len, dist = 0, 0
      if i + 2 < n then
        local a, b, c = byte(all, p - off, p - off + 2)
        local h = ((a * 33 + b) * 33 + c) % buckets + 1
        local cand = head[h]
        head[h] = p
        if cand > 0 and p - cand <= WINDOW and cand >= histStart then
          local max = math.min(longest, n - i)
          local l = 0
          while l < max and byte(all, cand - off + l) == byte(all, p - off + l) do l = l + 1 end
          if l >= 3 then len, dist = l, p - cand end
        end
      end
      if len >= 3 then
        local li = lengthIndex(len)
        local sym = 256 + li
        put(LCODE[sym], LLEN[sym])
        if LEXTRA[li] > 0 then put(len - LBASE[li], LEXTRA[li]) end
        local di = distIndex(dist)
        put(DCODE[di - 1], 5)
        if DEXTRA[di] > 0 then put(dist - DBASE[di], DEXTRA[di]) end
        -- the skipped positions go into the hash table too (cheaply: every one)
        for q = p + 1, math.min(p + len - 1, base + n - 3) do
          local a, b, c = byte(all, q - off, q - off + 2)
          head[((a * 33 + b) * 33 + c) % buckets + 1] = q
        end
        i = i + len
      else
        local s = byte(all, p - off)
        put(LCODE[s], LLEN[s])
        i = i + 1
      end
      if i % 1024 < 4 then breathe() end
    end
    put(LCODE[256], LLEN[256])
    -- data that does not shrink (already packed, random) goes in as it is
    if #out - saveN > n + 5 then
      for k = #out, saveN + 1, -1 do out[k] = nil end
      bitbuf, bitcnt = saveBuf, saveCnt
      put(final and 1 or 0, 1); put(0, 2)
      if bitcnt > 0 then put(0, 8 - bitcnt) end
      local len = string.char(n & 0xFF, n >> 8, ~n & 0xFF, (~n >> 8) & 0xFF)
      out[#out + 1] = len
      out[#out + 1] = data
    end
    -- keep the last WINDOW bytes for matches in the next block
    if #all > WINDOW then
      histStart = histStart + (#all - WINDOW)
      hist = all:sub(-WINDOW)
    else
      hist = all
    end
    flushOut()
  end

  local z = {}
  function z.write(data)
    pending = pending .. data
    while #pending >= BLOCK do
      local piece = pending:sub(1, BLOCK)
      pending = pending:sub(BLOCK + 1)
      block(piece, false)
    end
  end
  function z.finish()
    block(pending, true)
    pending = ""
    if bitcnt > 0 then put(0, 8 - bitcnt) end
    flushOut()
  end
  return z
end

local function le32(n)
  return string.char(n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF)
end

function deflate.gzipStream(sink, opts)
  opts = opts or {}
  local flags = opts.name and 8 or 0
  local level = opts.level or 6
  sink("\31\139\8" .. string.char(flags) .. le32(math.floor(opts.mtime or 0)) ..
    string.char(level >= 9 and 2 or level <= 1 and 4 or 0, 3) ..  -- extra flags, OS: Unix
    (opts.name and (opts.name:gsub("\0", "") .. "\0") or ""))
  local z = compressor(sink, level, breather(opts.breathe))
  local crc, size = 0, 0
  local g = {}
  function g.write(data)
    crc = deflate.crc32(data, crc); size = size + #data
    z.write(data)
  end
  function g.finish()
    z.finish()
    sink(le32(crc) .. le32(size & 0xFFFFFFFF))
  end
  return g
end

return deflate
