--[[
  time COMMAND... - run a command and say how long it took

    time pacman -Sy
    time sh build.sh

  Afterwards "real 1.25s" (wall-clock time, 1m02.50s past a minute) is
  printed; the exit status is the command's.
]]--
local args = arg or {}
if not args[1] then term.write("usage: time COMMAND...\n"); return 1 end
local words = {}
for _, w in ipairs(args) do
  words[#words + 1] = w:match("^[%w%-_./=:,+@%%]+$") and w or ("'" .. w:gsub("'", "'\\''") .. "'")
end
local line = table.concat(words, " ")

local start = computer.uptime()
local ok, rc
if stdio and (stdio.input or stdio.output) then
  ok, rc = pcall(shell.withIO, { input = stdio.input, output = stdio.output }, shell.execute, line)
else
  ok, rc = pcall(shell.execute, line)
end
local took = computer.uptime() - start
if not ok and rc == "__exit__" then ok, rc = true, shell.exitCode or 0 end
local m = math.floor(took / 60)
term.write(m > 0 and ("real %dm%05.2fs\n"):format(m, took - m * 60) or ("real %.2fs\n"):format(took))
if not ok then error(rc, 0) end
return tonumber(rc) or 0
