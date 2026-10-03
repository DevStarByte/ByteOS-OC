-- free - memory of this computer
local units = require("units")
local T = term.theme
local total, free = computer.totalMemory(), computer.freeMemory()
term.cwrite(T.bright, ("%-6s %8s %8s %8s\n"):format("", "total", "used", "free"))
term.write(("%-6s %8s %8s %8s\n"):format("Mem:", units.bytes(total), units.bytes(total - free), units.bytes(free)))
return 0
