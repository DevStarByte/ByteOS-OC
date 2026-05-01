-- mkdir - create directories
local args = arg or {}
if #args == 0 then term.write("mkdir: missing operand\n"); return 1 end
for _, a in ipairs(args) do
  local p = shell.normalize(a)
  if not k.fs.makeDirectory(p) then term.write("mkdir: cannot create '" .. a .. "'\n"); return 1 end
end
return 0
