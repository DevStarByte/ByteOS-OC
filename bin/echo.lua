-- echo - display a line of text
local args = arg or {}
term.write(table.concat(args, " ") .. "\n")
return 0
