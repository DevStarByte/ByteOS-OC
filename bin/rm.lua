-- rm <path>... - remove files, and directories with everything in them
-- (a symbolic link is removed itself, never what it points to)
local args = arg or {}
if #args == 0 then term.write("rm: missing operand\n"); return 1 end
for _, a in ipairs(args) do
  if a:sub(1,1) ~= "-" then
    local p = shell.normalize(a)
    if not k.fs.exists(p) and not k.fs.readlink(p) then term.write("rm: " .. a .. ": no such file\n"); return 1 end
    local ok, err = k.fs.remove(p)
    if not ok then term.write("rm: cannot remove '" .. a .. "': " .. tostring(err or "failed") .. "\n"); return 1 end
  end
end
return 0
