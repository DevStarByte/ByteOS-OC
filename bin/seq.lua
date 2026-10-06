--[[
  seq [-s SEP] [-w] LAST
  seq [-s SEP] [-w] FIRST LAST
  seq [-s SEP] [-w] FIRST STEP LAST
      print the numbers from FIRST (default 1) up to LAST, STEP apart
      (default 1; a negative STEP counts down)

    -s SEP   put SEP between the numbers instead of a new line
    -w       pad with leading zeros to the same width

  Handy in loops: for I in $(seq 5); echo $I; end
]]--
local args = arg or {}
local sep, wide, nums = "\n", false, {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-s" then i = i + 1; sep = (args[i] or ""):gsub("\\n", "\n"):gsub("\\t", "\t")
  elseif a == "-w" then wide = true
  elseif tonumber(a) then nums[#nums + 1] = tonumber(a)
  else term.write("seq: invalid number '" .. a .. "'\n"); return 1 end
  i = i + 1
end
if #nums == 0 or #nums > 3 then term.write("usage: seq [-s SEP] [-w] [FIRST] [STEP] LAST\n"); return 1 end
local first, step, last = 1, 1, nums[#nums]
if #nums >= 2 then first = nums[1] end
if #nums == 3 then step = nums[2] end
if step == 0 then term.write("seq: the step may not be 0\n"); return 1 end

local integers = math.type(first) == "integer" and math.type(step) == "integer" and math.type(last) == "integer"
local fmt = integers and "%d" or "%g"
if wide and integers then
  fmt = "%0" .. math.max(#("%d"):format(first), #("%d"):format(last)) .. "d"
end
local out, count = {}, 0
local n = first
while (step > 0 and n <= last) or (step < 0 and n >= last) do
  out[#out + 1] = fmt:format(n)
  count = count + 1
  if #out >= 200 then term.write(table.concat(out, sep) .. sep); out = {} end
  n = first + count * step -- not n + step: no rounding errors piling up
end
if #out > 0 then term.write(table.concat(out, sep)) end
if count > 0 then term.write("\n") end
return 0
