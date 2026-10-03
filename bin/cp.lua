-- cp <source> <target> - copy a file (target may be a directory)
local args = arg or {}
if #args < 2 then term.write("cp: missing operand\n"); return 1 end
local src = shell.normalize(args[1])
local dst = shell.normalize(args[2])
if not k.fs.exists(src) then term.write("cp: " .. args[1] .. ": no such file\n"); return 1 end
if k.fs.isDirectory(src) then term.write("cp: -r not supported yet\n"); return 1 end
local data, rerr = k.fs.readAll(src)
if not data then term.write("cp: " .. args[1] .. ": " .. tostring(rerr) .. "\n"); return 1 end
if k.fs.isDirectory(dst) then dst = dst .. "/" .. src:match("[^/]+$") end
local ok, err = k.fs.writeAll(dst, data)
if not ok then term.write("cp: cannot create '" .. args[2] .. "': " .. tostring(err) .. "\n"); return 1 end
return 0
