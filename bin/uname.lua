-- uname [-a|-r|-n|-m] - system name; -a all, -r release, -n host, -m machine
local args = arg or {}
local flag = args[1] or ""
local name, codename = "ByteOS", _G._OSCODENAME or "Iron"
local version = (_G._OSVERSION or ""):match("[%d%.]+") or "?"
local arch = "lua54"
local host = _G.HOSTNAME or "byteos"
if flag == "-a" then
  term.write(name .. " " .. host .. " " .. version .. " (" .. codename .. ") " .. arch .. " GNU/ByteOS\n")
elseif flag == "-r" then term.write(version .. "\n")
elseif flag == "-n" then term.write(host .. "\n")
elseif flag == "-m" then term.write(arch .. "\n")
else term.write(name .. "\n") end
return 0
