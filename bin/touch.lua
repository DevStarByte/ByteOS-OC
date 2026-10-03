-- touch file... - create empty files (existing ones are left as they are)
local args = arg or {}
if #args == 0 then term.write("touch: missing file operand\n"); return 1 end
local rc = 0
for _, a in ipairs(args) do
  local p = shell.normalize(a)
  if not fs.exists(p) then
    local f, err = fs.open(p, "w")
    if f then f:close() else term.write("touch: cannot touch '" .. a .. "': " .. tostring(err) .. "\n"); rc = 1 end
  end
end
return rc
