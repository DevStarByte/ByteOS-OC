--[[
  readlink [-f] PATH... - where a symbolic link points

    readlink ~/music       the target as it was given to ln -s
    readlink -f ~/music    the full path, every link on the way followed
                           (also works for paths that are not links)

  Status 1 when a PATH is not a link (without -f).
]]--
local args = arg or {}
local full, paths = false, {}
for _, a in ipairs(args) do
  if a == "-f" or a == "-e" or a == "-m" then full = true else paths[#paths + 1] = a end
end
if #paths == 0 then term.write("usage: readlink [-f] PATH...\n"); return 1 end
local rc = 0
for _, p in ipairs(paths) do
  local real = shell.normalize(p)
  local t, err
  if full then t, err = fs.realpath(real) else t = fs.readlink(real) end
  if t then term.write(t .. "\n")
  else
    if err then term.write("readlink: " .. p .. ": " .. err .. "\n") end
    rc = 1
  end
end
return rc
