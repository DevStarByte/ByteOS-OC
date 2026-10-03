--[[
  cp [-r] <source>... <target> - copy files; -r copies directories too

  With several sources, or when the target is a directory, the copies go
  into it: cp -r /etc /bin /mnt/1a2b3c4d/backup/
]]--
local files = require("files")
local args = arg or {}
local recursive, paths = false, {}
for _, a in ipairs(args) do
  if a == "-r" or a == "-R" then recursive = true else paths[#paths + 1] = a end
end
if #paths < 2 then term.write("usage: cp [-r] <source>... <target>\n"); return 1 end
local target = shell.normalize(table.remove(paths))
local intoDir = k.fs.isDirectory(target)
if #paths > 1 and not intoDir then term.write("cp: target '" .. target .. "' is not a directory\n"); return 1 end
local rc = 0
for _, p in ipairs(paths) do
  local src = shell.normalize(p)
  if not k.fs.exists(src) then
    term.write("cp: " .. p .. ": no such file or directory\n"); rc = 1
  else
    local dst = intoDir and files.join(target, src:match("[^/]+$") or "") or target
    local ok, err = files.copy(src, dst, recursive)
    if not ok then term.write("cp: " .. tostring(err) .. "\n"); rc = 1 end
  end
end
return rc
