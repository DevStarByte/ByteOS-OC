-- uname - print system information
local args = arg or {}
local flag = args[1] or ""
local name, version, codename = "ByteOS", "1.0.0", _G._OSCODENAME or "Iron"
local arch = "lua54"
local host = _G.HOSTNAME or "byteos"
if flag == "-a" then
  term.write(name .. " " .. host .. " " .. version .. " (" .. codename .. ") " .. arch .. " GNU/ByteOS\n")
elseif flag == "-r" then term.write(version .. "\n")
elseif flag == "-n" then term.write(host .. "\n")
elseif flag == "-m" then term.write(arch .. "\n")
else term.write(name .. "\n") end
return 0
