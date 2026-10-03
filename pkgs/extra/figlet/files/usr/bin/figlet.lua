-- Tiny figlet stub: prints big block letters by looking up a static font.
-- This is a demo of bundling large data files inside a compressed package.
local fontPath = "/usr/share/figlet/standard.flf"
local ok, raw  = pcall(function() return fs.readAll(fontPath) end)
if not ok or not raw then
  term.write("figlet: missing font: " .. fontPath .. "\n")
  return 1
end
local msg = table.concat(arg or {}, " ")
if msg == "" then msg = "ByteOS" end
term.write(("figlet> %s\n"):format(msg))
term.write("(font loaded, " .. #raw .. " bytes -- real renderer not implemented)\n")
return 0
