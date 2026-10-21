-- tac [FILE...] - print the lines of each file (or of the input) last line first
local args = arg or {}
local files = #args > 0 and args or { "-" }
local rc = 0
for _, f in ipairs(files) do
  local text, err
  if f == "-" then text = stdin.read("a") or "" else text, err = fs.readAll(shell.normalize(f)) end
  if not text then term.write("tac: " .. f .. ": " .. tostring(err or "no such file") .. "\n"); rc = 1
  elseif text ~= "" then
    if text:sub(-1) ~= "\n" then text = text .. "\n" end
    local lines = {}
    for l in text:gmatch("([^\n]*\n)") do lines[#lines + 1] = l end
    local out = {}
    for i = #lines, 1, -1 do out[#out + 1] = lines[i] end
    term.write(table.concat(out))
  end
end
return rc
