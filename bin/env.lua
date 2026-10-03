--[[
  env                         list the variables
  env NAME=value... command   run a command with variables set just for it
]]--
local args = arg or {}
local set, i = {}, 1
while args[i] and args[i]:match("^[%w_]+=") do
  local name, value = args[i]:match("^([%w_]+)=(.*)$")
  if not shell.validName(name) or name == "USER" or name == "HOME" or name == "LOGNAME" then
    term.write("env: cannot set " .. name .. "\n"); return 1
  end
  set[#set + 1] = { name, value }
  i = i + 1
end
if not args[i] then
  local names = {}
  for name, v in pairs(_G) do
    if shell.validName(name) and (type(v) == "string" or type(v) == "number") then names[#names + 1] = name end
  end
  for _, s in ipairs(set) do if _G[s[1]] == nil then names[#names + 1] = s[1] end end
  table.sort(names)
  for _, name in ipairs(names) do
    local v = _G[name]
    for _, s in ipairs(set) do if s[1] == name then v = s[2] end end
    term.write(name .. "=" .. tostring(v) .. "\n")
  end
  return 0
end
local line = {}
for j = i, #args do
  local a = args[j]
  if not a:find("[%s\"']") then line[#line + 1] = a
  elseif not a:find('"', 1, true) then line[#line + 1] = '"' .. a .. '"'
  else line[#line + 1] = "'" .. a .. "'" end
end
local saved = {}
for _, s in ipairs(set) do saved[s[1]] = _G[s[1]]; _G[s[1]] = s[2] end
local ok, rc = pcall(shell.run, table.concat(line, " "), stdio)
for _, s in ipairs(set) do _G[s[1]] = saved[s[1]] end
if not ok then error(rc, 0) end
return rc
