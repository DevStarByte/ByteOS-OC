-- echo [text...] - print the words, separated by spaces
local args = arg or {}
term.write(table.concat(args, " ") .. "\n")
return 0
