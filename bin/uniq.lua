--[[
  uniq [-c] [-d] [-u] [-i] [FILE] - drop repeated lines that follow each other

    -c   put how often each line came before it
    -d   only lines that were repeated
    -u   only lines that were not repeated
    -i   ignore upper/lower case when comparing

  Only neighbours are compared, so sort first: sort names.txt | uniq -c
]]--
local args = arg or {}
local opt, file = {}, nil
for _, a in ipairs(args) do
  if a:match("^%-%a+$") then for f in a:sub(2):gmatch(".") do opt[f] = true end
  else file = a end
end
local text, err
if file then text, err = fs.readAll(shell.normalize(file)) else text = stdin.read("a") or "" end
if not text then term.write("uniq: " .. file .. ": " .. tostring(err) .. "\n"); return 1 end
if text ~= "" and text:sub(-1) ~= "\n" then text = text .. "\n" end

local prev, prevKey, count = nil, nil, 0
local function flush()
  if not prev then return end
  if (opt.d and count < 2) or (opt.u and count > 1) then return end
  term.write((opt.c and ("%7d "):format(count) or "") .. prev .. "\n")
end
for line in text:gmatch("([^\n]*)\n") do
  local key = opt.i and line:lower() or line
  if key == prevKey then
    count = count + 1
  else
    flush()
    prev, prevKey, count = line, key, 1
  end
end
flush()
return 0
