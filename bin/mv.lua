--[[
  mv <source>... <target> - move or rename files and directories

  With several sources, or when the target is a directory, they go into
  it. Onto another disk, mv copies and then removes the original.
]]--
local files = require("files")
local args = arg or {}
if #args < 2 then term.write("usage: mv <source>... <target>\n"); return 1 end
local paths = { table.unpack(args) }
local target = shell.normalize(table.remove(paths))
local intoDir = k.fs.isDirectory(target)
if #paths > 1 and not intoDir then term.write("mv: target '" .. target .. "' is not a directory\n"); return 1 end
local rc = 0
for _, p in ipairs(paths) do
  local src = shell.normalize(p)
  local dst = intoDir and files.join(target, src:match("[^/]+$") or "") or target
  local ok, err
  if not k.fs.exists(src) then
    ok, err = nil, "no such file or directory"
  elseif dst == src or dst:sub(1, #src + 1) == src .. "/" then
    ok, err = nil, "cannot move it into itself"
  else
    ok, err = k.fs.rename(src, dst)
    if not ok and err == "cross-device" then
      ok, err = files.copy(src, dst, true)
      if ok then ok, err = k.fs.remove(src) end
    end
  end
  if not ok then term.write("mv: cannot move '" .. p .. "': " .. tostring(err or "failed") .. "\n"); rc = 1 end
end
return rc
