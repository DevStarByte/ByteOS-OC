--[[
  yes [STRING...]   print "y" (or STRING) over and over, until Ctrl+C

    yes | sudo pacman -S cowsay      answer every question with y

  Pipes in ByteOS are not streams: each command runs to its end before
  the next one starts. So into a pipe or a file yes stops by itself after
  1000 lines, more than any program asks for.
]]--
local args = arg or {}
local line = (#args > 0 and table.concat(args, " ") or "y") .. "\n"
if stdio and stdio.output then
  term.write(string.rep(line, 1000))
  return 0
end
-- on the screen: forever, with a pause now and then so Ctrl+C gets
-- through and OpenComputers does not stop the computer for running too long
local chunk = string.rep(line, 20)
while true do
  term.write(chunk)
  k.event.pull(0)
end
