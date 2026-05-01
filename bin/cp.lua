-- cp - copy file
local args = arg or {}
if #args < 2 then term.write("cp: missing operand\n"); return 1 end
local src = shell.normalize(args[1])
local dst = shell.normalize(args[2])
if not k.fs.exists(src) then term.write("cp: " .. args[1] .. ": no such file\n"); return 1 end
if k.fs.isDirectory(src) then term.write("cp: -r not supported yet\n"); return 1 end
local data = k.fs.readAll(src)
if k.fs.isDirectory(dst) then dst = dst .. "/" .. src:match("[^/]+$") end
k.fs.writeAll(dst, data)
return 0
