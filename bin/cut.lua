--[[
  cut -f LIST [-d SEP] [-s] [FILE...]   print only some fields of each line
  cut -c LIST [FILE...]                 print only some characters

    -f LIST  fields, separated by SEP (default a tab)
    -d SEP   the field separator, one character
    -s       skip lines that do not contain SEP
    -c LIST  character positions

  LIST is numbers and ranges: 1,3   2-4   -2 (up to 2)   3- (from 3)

    cut -d : -f 1 /etc/passwd       the user names
]]--
local args = arg or {}
local fields, chars, sep, onlyDelim, files = nil, nil, "\t", false, {}
local i = 1
while i <= #args do
  local a = args[i]
  local opt, val = a:match("^%-([fcd])(.*)$")
  if opt then
    if val == "" then i = i + 1; val = args[i] or "" end
    if opt == "f" then fields = val elseif opt == "c" then chars = val else sep = val end
  elseif a == "-s" then onlyDelim = true
  else files[#files + 1] = a end
  i = i + 1
end
if not fields and not chars then term.write("usage: cut -f LIST [-d SEP] [FILE...]  or  cut -c LIST [FILE...]\n"); return 1 end
if #sep ~= 1 then term.write("cut: the separator must be one character\n"); return 1 end

-- "1,3-4,6-" -> { {1,1}, {3,4}, {6,huge} }
local ranges = {}
for part in (fields or chars):gmatch("[^,]+") do
  local a, b = part:match("^(%d*)%-(%d*)$")
  if a then
    ranges[#ranges + 1] = { tonumber(a) or 1, tonumber(b) or math.huge }
  elseif tonumber(part) then
    ranges[#ranges + 1] = { tonumber(part), tonumber(part) }
  else
    term.write("cut: invalid list '" .. (fields or chars) .. "'\n"); return 1
  end
end
local function wanted(n)
  for _, r in ipairs(ranges) do if n >= r[1] and n <= r[2] then return true end end
  return false
end

if #files == 0 then files = { "-" } end
for _, f in ipairs(files) do
  local text, err
  if f == "-" then text = stdin.read("a") or "" else text, err = fs.readAll(shell.normalize(f)) end
  if not text then term.write("cut: " .. f .. ": " .. tostring(err or "no such file") .. "\n"); return 1 end
  if text ~= "" and text:sub(-1) ~= "\n" then text = text .. "\n" end
  local out = {}
  for line in text:gmatch("([^\n]*)\n") do
    if chars then
      local picked, n = {}, 0
      for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
        if wanted(n) then picked[#picked + 1] = ch end
      end
      out[#out + 1] = table.concat(picked)
    elseif not line:find(sep, 1, true) then
      if not onlyDelim then out[#out + 1] = line end
    else
      local picked, n = {}, 0
      for part in (line .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
        n = n + 1
        if wanted(n) then picked[#picked + 1] = part end
      end
      out[#out + 1] = table.concat(picked, sep)
    end
  end
  if #out > 0 then term.write(table.concat(out, "\n") .. "\n") end
end
return 0
