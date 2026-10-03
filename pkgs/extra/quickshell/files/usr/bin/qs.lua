--[[
  qs - the short name of quickshell (see man quickshell)
]]--
return shell.run("quickshell " .. table.concat(arg or {}, " "))
