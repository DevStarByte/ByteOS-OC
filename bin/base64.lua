--[[
  base64 [-d] [-w COLS] [FILE]   encode a file (or the input) as base64 text,
                                 or with -d decode it again

    -w COLS   wrap lines after COLS characters (default 76, 0: no wrap)
    -d        decode; line breaks and spaces in the input are ignored

    base64 picture.bin > picture.txt      text that survives copy and paste
]]--
local args = arg or {}
local decode, wrap, file = false, 76, nil
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-d" or a == "--decode" then decode = true
  elseif a:match("^%-w") then
    local v = a:sub(3)
    if v == "" then i = i + 1; v = args[i] end
    wrap = tonumber(v)
    if not wrap then term.write("base64: invalid wrap size\n"); return 1 end
  elseif file then term.write("usage: base64 [-d] [-w COLS] [FILE]\n"); return 1
  else file = a end
  i = i + 1
end
local text, err
if not file or file == "-" then text = stdin.read("a") or "" else text, err = fs.readAll(shell.normalize(file)) end
if not text then term.write("base64: " .. file .. ": " .. tostring(err or "no such file") .. "\n"); return 1 end

local ABC = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
if decode then
  local value = {}
  for n = 1, 64 do value[ABC:byte(n)] = n - 1 end
  text = text:gsub("[%s=]", "")
  if text:find("[^%w%+/]") then term.write("base64: invalid input\n"); return 1 end
  local out = {}
  for n = 1, #text, 4 do
    local q = text:sub(n, n + 3)
    local v, bits = 0, 0
    for c = 1, #q do v = (v << 6) | value[q:byte(c)]; bits = bits + 6 end
    local bytes = bits // 8
    v = v >> (bits - bytes * 8)
    for b = bytes - 1, 0, -1 do out[#out + 1] = string.char((v >> (b * 8)) & 255) end
  end
  term.write(table.concat(out))
  return 0
end

local out = {}
for n = 1, #text, 3 do
  local a, b, c = text:byte(n, n + 2)
  local v = (a << 16) | ((b or 0) << 8) | (c or 0)
  local s = {}
  for k_ = 3, 0, -1 do s[#s + 1] = ABC:sub(((v >> (k_ * 6)) & 63) + 1, ((v >> (k_ * 6)) & 63) + 1) end
  if not b then s[3], s[4] = "=", "=" elseif not c then s[4] = "=" end
  out[#out + 1] = table.concat(s)
end
local enc = table.concat(out)
if enc == "" then return 0 end
if wrap > 0 then
  local lines = {}
  for n = 1, #enc, wrap do lines[#lines + 1] = enc:sub(n, n + wrap - 1) end
  enc = table.concat(lines, "\n")
end
term.write(enc .. "\n")
return 0
