--[[
  paste [-d LIST] [-s] FILE...   join the lines of files side by side

    paste a b        line 1 of a, a tab, line 1 of b; then line 2 ...
    -d LIST          use these characters between the columns (in turn)
    -s               one file at a time: all its lines on one line

  - as a file name reads the input.
]]--
local args = arg or {}
local delims, serial, files = "\t", false, {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-s" then serial = true
  elseif a:match("^%-d") then
    local v = a:sub(3)
    if v == "" then i = i + 1; v = args[i] or "" end
    delims = v:gsub("\\t", "\t"):gsub("\\n", "\n"):gsub("\\0", "")
  else files[#files + 1] = a end
  i = i + 1
end
if #files == 0 then files = { "-" } end
local dl = {}
for ch in delims:gmatch("[%z\1-\127\194-\244][\128-\191]*") do dl[#dl + 1] = ch end
local function delim(n) return #dl > 0 and dl[(n - 1) % #dl + 1] or "" end

local columns, stdinText = {}, nil
for idx, f in ipairs(files) do
  local text, err
  if f == "-" then stdinText = stdinText or stdin.read("a") or ""; text = stdinText
  else text, err = fs.readAll(shell.normalize(f)) end
  if not text then term.write("paste: " .. f .. ": " .. tostring(err or "no such file") .. "\n"); return 1 end
  local lines = {}
  if text ~= "" and text:sub(-1) ~= "\n" then text = text .. "\n" end
  for l in text:gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
  columns[idx] = lines
end

local out = {}
if serial then
  for _, lines in ipairs(columns) do
    local parts = {}
    for n, l in ipairs(lines) do parts[#parts + 1] = (n > 1 and delim(n - 1) or "") .. l end
    out[#out + 1] = table.concat(parts)
  end
else
  local rows = 0
  for _, lines in ipairs(columns) do rows = math.max(rows, #lines) end
  for r = 1, rows do
    local parts = {}
    for c, lines in ipairs(columns) do parts[#parts + 1] = (c > 1 and delim(c - 1) or "") .. (lines[r] or "") end
    out[#out + 1] = table.concat(parts)
  end
end
if #out > 0 then term.write(table.concat(out, "\n") .. "\n") end
return 0
