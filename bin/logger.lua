-- logger [-t tag] message... - write a line to the system log
local args = arg or {}
local tag = k.user()
if args[1] == "-t" then tag = args[2]; table.remove(args, 1); table.remove(args, 1) end
if #args == 0 then term.write("usage: logger [-t tag] message...\n"); return 1 end
k.log(table.concat(args, " "), tag)
return 0
