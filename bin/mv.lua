-- mv - move/rename
local args = arg or {}
if #args < 2 then term.write("mv: missing operand\n"); return 1 end
local src = shell.normalize(args[1])
local dst = shell.normalize(args[2])
local ok, err = k.fs.rename(src, dst)
if not ok and err == "cross-device" then
  -- another disk: copy, then delete the original
  local data, rerr = k.fs.readAll(src)
  if not data then term.write("mv: " .. args[1] .. ": " .. tostring(rerr) .. "\n"); return 1 end
  ok, err = k.fs.writeAll(dst, data)
  if ok then ok, err = k.fs.remove(src) end
end
if not ok then
  term.write("mv: cannot move '" .. args[1] .. "': " .. tostring(err or "failed") .. "\n")
  return 1
end
return 0
