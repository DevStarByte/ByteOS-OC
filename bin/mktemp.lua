--[[
  mktemp [-d] [TEMPLATE] - create a new empty file (or with -d a
  directory) with a unique name and print the name

    TEMPLATE ends in XXX...; the X are replaced by random letters and
    digits (default /tmp/tmp.XXXXXX)

    F=$(mktemp); ls > $F
]]--
local args = arg or {}
local dir, template = false, nil
for _, a in ipairs(args) do
  if a == "-d" then dir = true else template = a end
end
template = template or "/tmp/tmp.XXXXXX"
local xs = template:match("X+$")
if not xs or #xs < 3 then term.write("mktemp: the template must end in at least 3 X\n"); return 1 end
local CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
for _ = 1, 100 do
  local r = {}
  for i = 1, #xs do
    local n = math.random(#CHARS)
    r[i] = CHARS:sub(n, n)
  end
  local path = shell.normalize(template:sub(1, -#xs - 1) .. table.concat(r))
  if not fs.exists(path) then
    local ok, err
    if dir then ok, err = fs.makeDirectory(path) else ok, err = fs.writeAll(path, "") end
    if not ok then term.write("mktemp: " .. path .. ": " .. tostring(err) .. "\n"); return 1 end
    term.write(path .. "\n")
    return 0
  end
end
term.write("mktemp: no free name for " .. template .. "\n")
return 1
