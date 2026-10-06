--[[
  tr SET1 SET2       replace each character of SET1 by the one at the
                     same place in SET2 (the last one of SET2 if it is shorter)
  tr -d SET1         delete the characters of SET1
  tr -s SET1 [SET2]  squeeze repeats of a character (of SET1, or of SET2
                     after replacing) into one

  Sets: a-z ranges, \n \t \\ and [:upper:] [:lower:] [:alpha:] [:digit:]
  [:alnum:] [:space:] [:punct:]. Works on bytes, so plain ASCII only.

    echo hello | tr a-z A-Z        tr -d '\r' < dos.txt
]]--
local args = arg or {}
local del, squeeze, sets = false, false, {}
for _, a in ipairs(args) do
  if a:match("^%-[ds]+$") then
    if a:find("d") then del = true end
    if a:find("s") then squeeze = true end
  else sets[#sets + 1] = a end
end
local usage = "usage: tr [-d] [-s] SET1 [SET2]\n"
if #sets == 0 or (not del and not squeeze and #sets < 2) then term.write(usage); return 1 end

local CLASSES = { upper = "%u", lower = "%l", alpha = "%a", digit = "%d", alnum = "%w", space = "%s", punct = "%p" }
local function expand(set)
  local out, i = {}, 1
  set = set:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\r", "\r"):gsub("\\\\", "\\")
  while i <= #set do
    local class = set:match("^%[:(%a+):%]", i)
    if class and CLASSES[class] then
      for b = 0, 127 do
        local c = string.char(b)
        if c:match(CLASSES[class]) then out[#out + 1] = c end
      end
      i = i + #class + 4
    elseif set:sub(i + 1, i + 1) == "-" and i + 2 <= #set then
      for b = set:byte(i), set:byte(i + 2) do out[#out + 1] = string.char(b) end
      i = i + 3
    else
      out[#out + 1] = set:sub(i, i); i = i + 1
    end
  end
  return out
end

local s1, s2 = expand(sets[1]), sets[2] and expand(sets[2]) or nil
local map, inSet1, squeezeSet = {}, {}, {}
for idx, c in ipairs(s1) do
  inSet1[c] = true
  if s2 and not del then map[c] = s2[math.min(idx, #s2)] end
end
if squeeze then -- the characters that come out: SET2 if there is one
  for _, c in ipairs(s2 or s1) do squeezeSet[c] = true end
end

local text = stdin.read("a") or ""
local out, last = {}, nil
for c in text:gmatch(".") do
  if not (del and inSet1[c]) then
    c = map[c] or c
    if not (squeeze and squeezeSet[c] and c == last) then out[#out + 1] = c end
    last = c
  end
end
term.write(table.concat(out))
return 0
