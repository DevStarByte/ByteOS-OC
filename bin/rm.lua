-- rm - remove files or directories
local args = arg or {}
if #args == 0 then term.write("rm: missing operand\n"); return 1 end
for _, a in ipairs(args) do
  if a:sub(1,1) ~= "-" then
    local p = shell.normalize(a)
    if not k.fs.exists(p) then term.write("rm: " .. a .. ": no such file\n"); return 1 end
    k.fs.remove(p)
  end
end
return 0
