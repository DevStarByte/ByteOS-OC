-- ls - list directory contents
local args = arg or {}
local path = args[1] or _G.PWD or "/"
path = shell.normalize(path)
if not k.fs.exists(path) then term.write("ls: " .. path .. ": no such file or directory\n"); return 1 end
if not k.fs.isDirectory(path) then term.write(path .. "\n"); return 0 end

local entries = k.fs.list(path)
local cols, _ = term.size()
local maxlen = 0
for _, e in ipairs(entries) do if #e > maxlen then maxlen = #e end end
local colw = maxlen + 2
local perrow = math.max(1, math.floor(cols / colw))
local i = 0
for _, e in ipairs(entries) do
  local full = (path == "/" and "/" or path .. "/") .. e:gsub("/$", "")
  if k.fs.isDirectory(full) then term.setForeground(0x55AAFF) else term.setForeground(0xFFFFFF) end
  term.write(e .. string.rep(" ", colw - #e))
  i = i + 1
  if i % perrow == 0 then term.write("\n") end
end
if i % perrow ~= 0 then term.write("\n") end
term.setForeground(0xFFFFFF)
return 0
