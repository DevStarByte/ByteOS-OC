-- mv - move/rename
local args = arg or {}
if #args < 2 then term.write("mv: missing operand\n"); return 1 end
local src = shell.normalize(args[1])
local dst = shell.normalize(args[2])
local ok, err = k.fs.rename(src, dst)
if not ok then
  -- fall back to copy+delete (cross-device)
  local data = k.fs.readAll(src)
  if not data then term.write("mv: " .. tostring(err) .. "\n"); return 1 end
  k.fs.writeAll(dst, data)
  k.fs.remove(src)
end
return 0
