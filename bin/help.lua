-- help - list available commands
term.write("ByteOS - available commands:\n")
local seen = {}
for dir in (_G.PATH or "/bin:/usr/bin:/sbin"):gmatch("[^:]+") do
  if k.fs.isDirectory(dir) then
    for _, e in ipairs(k.fs.list(dir)) do
      local name = e:gsub("%.lua$", ""):gsub("/$", "")
      if not seen[name] then seen[name] = true end
    end
  end
end
for name in pairs(seen) do term.write("  " .. name .. "\n") end
term.write("\nBuilt-ins: cd, exit, export, set\n")
return 0
