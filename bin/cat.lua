-- cat - concatenate and print files
local args = arg or {}
if #args == 0 then term.write("cat: missing file operand\n"); return 1 end
for _, a in ipairs(args) do
  local p = shell.normalize(a)
  if not k.fs.exists(p) then term.write("cat: " .. a .. ": no such file\n"); return 1 end
  if k.fs.isDirectory(p) then term.write("cat: " .. a .. ": is a directory\n"); return 1 end
  local data, err = k.fs.readAll(p)
  if not data then term.write("cat: " .. a .. ": " .. tostring(err) .. "\n"); return 1 end
  term.write(data)
  if data:sub(-1) ~= "\n" then term.write("\n") end
end
return 0
