--[[
  sort [-r] [-n] [-u] [-f] [-k N] [-t SEP] [FILE...] - print the lines sorted

    -r       reverse order
    -n       by the number at the start of the line (or field)
    -u       each line only once
    -f       ignore upper/lower case
    -k N     by the N-th field instead of the whole line
    -t SEP   fields are separated by SEP (default: spaces and tabs)

    du /home | sort -n -r      ls /bin | sort -r
]]--
local args = arg or {}
local opt, field, sep, files = {}, nil, nil, {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-k" then i = i + 1; field = tonumber((args[i] or ""):match("^%d+"))
  elseif a == "-t" then i = i + 1; sep = args[i]
  elseif a:match("^%-%a+$") then for f in a:sub(2):gmatch(".") do opt[f] = true end
  else files[#files + 1] = a end
  i = i + 1
end
if #files == 0 then files = { "-" } end

local items = {}
for _, f in ipairs(files) do
  local text, err
  if f == "-" then text = stdin.read("a") or "" else text, err = fs.readAll(shell.normalize(f)) end
  if not text then term.write("sort: " .. f .. ": " .. tostring(err or "no such file") .. "\n"); return 2 end
  if text ~= "" and text:sub(-1) ~= "\n" then text = text .. "\n" end
  for line in text:gmatch("([^\n]*)\n") do items[#items + 1] = { line = line } end
end

local function fieldOf(line)
  local n = 0
  local text, pat = line, "%S+"
  if sep then text, pat = line .. sep, "(.-)" .. sep:gsub("%p", "%%%0") end
  for part in text:gmatch(pat) do
    n = n + 1
    if n == field then return part end
  end
  return ""
end
local function keyOf(line)
  if field then line = fieldOf(line) end
  if opt.f then line = line:lower() end
  return line
end
for idx, it in ipairs(items) do
  it.key, it.idx = keyOf(it.line), idx
  if opt.n then it.num = tonumber(it.key:match("^%s*([%+%-]?%d*%.?%d+)")) or 0 end
end

table.sort(items, function(a, b)
  local x, y = a, b
  if opt.r then x, y = b, a end
  if opt.n and x.num ~= y.num then return x.num < y.num end
  if x.key ~= y.key then return x.key < y.key end
  return a.idx < b.idx -- equal lines keep their order
end)

local out, last = {}, nil
for _, it in ipairs(items) do
  if not (opt.u and it.key == last) then out[#out + 1] = it.line end
  last = it.key
end
if #out > 0 then term.write(table.concat(out, "\n") .. "\n") end
return 0
