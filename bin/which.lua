-- which command... - where a command comes from (alias, built-in or file)
local args = arg or {}
if #args == 0 then term.write("usage: which command...\n"); return 1 end
local rc = 0
for _, name in ipairs(args) do
  if shell.aliases[name] then term.write(name .. ": aliased to " .. shell.aliases[name] .. "\n")
  elseif shell.builtins[name] then term.write(name .. ": shell built-in command\n")
  else
    local path = shell.resolveBin(name)
    if path then term.write(path .. "\n")
    else term.write("which: no " .. name .. " in (" .. tostring(_G.PATH) .. ")\n"); rc = 1 end
  end
end
return rc
