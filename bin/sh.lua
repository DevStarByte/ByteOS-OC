--[[
  sh - ByteShell

    sh                  an interactive shell; exit returns
    sh script [args]    run a script ($0 $1 ... $# $@ inside it)
    sh -c "commands"    run commands

  A script is a text file of shell lines. With `#!/bin/sh` as its first
  line it also runs by its name (./script or from $PATH).
]]--
local args = arg or {}
if args[1] == "-c" then
  local ok, rc = pcall(shell.withIO, stdio, shell.execute, table.concat(args, " ", 2))
  if not ok then
    if rc == "__exit__" then return shell.exitCode or 0 end
    error(rc, 0)
  end
  return rc
end
if args[1] then
  local path = shell.normalize(args[1])
  if not fs.exists(path) then term.write("sh: " .. args[1] .. ": no such file\n"); return 127 end
  return shell.runScript(path, { table.unpack(args, 2) }, stdio)
end
shell.loop(nil, true)
return 0
