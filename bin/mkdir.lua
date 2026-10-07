-- mkdir <dir>... - create directories (missing parents too)
local args = arg or {}
if #args == 0 then term.write("mkdir: missing operand\n"); return 1 end
for _, a in ipairs(args) do
  local p = shell.normalize(a)
  local ok, err = k.fs.makeDirectory(p)
  if not ok then
    term.write("mkdir: cannot create '" .. a .. "'" .. (err and (": " .. err) or "") .. "\n")
    return 1
  end
end
return 0
