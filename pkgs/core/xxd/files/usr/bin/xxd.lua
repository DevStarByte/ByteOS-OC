--[[
  xxd - show a file's bytes in hex, or turn such a dump back into bytes

    xxd [FILE]            00000000: 4865 6c6c 6f0a  Hello.
    -c COLS               bytes per line (16; 30 with -p)
    -g N                  bytes per group (2; 0 for one block)
    -s SKIP               start SKIP bytes in (0x.. for hex)
    -l LEN                stop after LEN bytes
    -p                    plain hex, no offsets or text
    -r                    the other way: a dump (normal or -p) back to bytes
                          xxd -r dump.txt > file.bin

  Without FILE it reads its input: cat /bin/ls.lua | xxd | head. As vim's
  xxd: the text column shows printable ASCII, a . for everything else.
]]--
local args = arg or {}
local cols, group, skip, len, plain, reverse, file
local function num(s)
  if not s then return nil end
  if s:match("^0[xX]%x+$") then return tonumber(s:sub(3), 16) end
  return tonumber(s)
end
local i = 1
while i <= #args do
  local a = args[i]
  local opt, val = a:match("^%-(%a)(.*)$")
  if opt == "p" and val == "" then plain = true
  elseif opt == "r" and val == "" then reverse = true
  elseif opt == "r" and val == "p" or (opt == "p" and val == "r") then plain, reverse = true, true
  elseif opt == "c" or opt == "g" or opt == "s" or opt == "l" then
    if val == "" then i = i + 1; val = args[i] end
    local n = num(val)
    if not n or n < 0 then term.write("xxd: -" .. opt .. " needs a number\n"); return 2 end
    if opt == "c" then cols = n elseif opt == "g" then group = n elseif opt == "s" then skip = n else len = n end
  elseif opt then term.write("xxd: unknown option " .. a .. "\n"); return 2
  else file = a end
  i = i + 1
end

local data, err
if file and file ~= "-" then data, err = fs.readAll(shell.normalize(file))
else data = stdin.read("a") or "" end
if not data then term.write("xxd: " .. file .. ": " .. tostring(err or "cannot read") .. "\n"); return 1 end

-- ---- -r: hex back to bytes -------------------------------------------------------------
if reverse then
  -- bytes go into a pipe or file as they are (term would treat them as text)
  local function emit(s)
    if stdio and stdio.output then stdio.output[#stdio.output + 1] = s else term.write(s) end
  end
  local out, size = {}, 0
  local function bytesOf(hex)
    local parts = {}
    for pair in hex:gmatch("%x%x") do parts[#parts + 1] = string.char(tonumber(pair, 16)) end
    return table.concat(parts)
  end
  if plain then
    emit(bytesOf((data:gsub("%X", ""))))
    return 0
  end
  for line in data:gmatch("[^\n]+") do
    local off, rest = line:match("^%s*(%x+):%s?(.*)$")
    if off then
      off = tonumber(off, 16)
      -- the hex ends where the text column starts (two spaces)
      local hex = rest:match("^(.-)  ") or rest
      local bytes = bytesOf(hex:gsub("%s", ""))
      if off > size then out[#out + 1] = ("\0"):rep(off - size); size = off end
      if off == size then out[#out + 1] = bytes; size = size + #bytes end
    end
  end
  emit(table.concat(out))
  return 0
end

-- ---- the dump ------------------------------------------------------------------------------
skip = skip or 0
local last = len and math.min(#data, skip + len) or #data
if plain then
  cols = (cols and cols > 0) and cols or 30
  for at = skip + 1, last, cols do
    local hex = {}
    for p = at, math.min(at + cols - 1, last) do hex[#hex + 1] = ("%02x"):format(data:byte(p)) end
    term.write(table.concat(hex) .. "\n")
    if at % 4096 < cols then k.event.pull(0) end
  end
  return 0
end
cols = (cols and cols > 0) and cols or 16
group = group or 2
if group == 0 or group > cols then group = cols end
local groups = (cols + group - 1) // group
local width = cols * 2 + groups - 1 -- the hex column of a full line
for at = skip + 1, last, cols do
  local hex, text = {}, {}
  local stop = math.min(at + cols - 1, last)
  for p = at, stop do
    local b = data:byte(p)
    hex[#hex + 1] = ("%02x"):format(b)
    if (p - at + 1) % group == 0 and p < stop then hex[#hex + 1] = " " end
    text[#text + 1] = (b >= 32 and b < 127) and string.char(b) or "."
  end
  local h = table.concat(hex)
  term.write(("%08x: %s  %s\n"):format(at - 1, h .. (" "):rep(width - #h), table.concat(text)))
  if at % 4096 < cols then k.event.pull(0) end
end
return 0
