--[[
  start-hyprbyte - start Hyprbyte on the screen (see man hyprbyte)

  Hyprbyte is not a login session: log in to ByteShell, then type
  start-hyprbyte. Mod+Shift+E quits it and returns to the shell.
]]--
return shell.run("hyprbyte " .. table.concat(arg or {}, " "))
