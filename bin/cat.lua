-- cat [file...] - print files; without files (or with -) its input,
-- e.g. from a pipe or `cat < file`
local args = arg or {}
if #args == 0 then args = { "-" } end
for _, a in ipairs(args) do
  local data
  if a == "-" then
    data = stdin.read("a") or ""
  else
    local p = shell.normalize(a)
    if not k.fs.exists(p) then term.write("cat: " .. a .. ": no such file\n"); return 1 end
    if k.fs.isDirectory(p) then term.write("cat: " .. a .. ": is a directory\n"); return 1 end
    local err
    data, err = k.fs.readAll(p)
    if not data then term.write("cat: " .. a .. ": " .. tostring(err) .. "\n"); return 1 end
  end
  term.write(data)
  if data ~= "" and data:sub(-1) ~= "\n" and stdin.isTerminal then term.write("\n") end
end
return 0
