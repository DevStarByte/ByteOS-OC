--[[
  basename PATH [SUFFIX] - the last part of PATH, without SUFFIX

    basename /etc/pacman.conf        pacman.conf
    basename /home/alice/notes.txt .txt   notes
]]--
local args = arg or {}
if not args[1] then term.write("usage: basename PATH [SUFFIX]\n"); return 1 end
local path = args[1]:gsub("/+$", "")
local name = path == "" and "/" or path:match("[^/]*$")
local suffix = args[2]
if suffix and suffix ~= name and name:sub(-#suffix) == suffix then name = name:sub(1, -#suffix - 1) end
term.write(name .. "\n")
return 0
