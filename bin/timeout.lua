--[[
  timeout DURATION COMMAND... - stop a command that takes too long

    timeout 10 ping box2       give up after 10 seconds
    timeout 1.5m pacman -Sy    DURATION in seconds, or with s, m, h, d

  The exit status is the command's, or 124 when it had to be stopped.
  The command runs as a background process while timeout waits, so it
  cannot read the keyboard; Ctrl+C stops both. -s SIGNAL is accepted for
  scripts from Linux, but there are no signals: the command is stopped.
]]--
local args = arg or {}
local i = 1
while args[i] and args[i]:sub(1, 1) == "-" and not args[i]:match("^%-?%d") do
  local a = args[i]
  if a == "-s" or a == "--signal" or a == "-k" or a == "--kill-after" then i = i + 1
  elseif a == "--preserve-status" or a == "--foreground" then -- nothing to do
  elseif a == "--" then i = i + 1; break
  else shell.err("timeout", "unknown option " .. a); return 125 end
  i = i + 1
end
local n, unit = tostring(args[i] or ""):match("^(%d*%.?%d+)([smhd]?)$")
if not n or not args[i + 1] then term.write("usage: timeout DURATION COMMAND...\n"); return 125 end
local secs = tonumber(n) * ({ s = 1, m = 60, h = 3600, d = 86400 })[unit ~= "" and unit or "s"]

local words = {}
for j = i + 1, #args do
  local w = args[j]
  words[#words + 1] = w:match("^[%w%-_./=:,+@%%]+$") and w or ("'" .. w:gsub("'", "'\\''") .. "'")
end
local line = table.concat(words, " ")

-- what the command reads and prints stays where timeout's own would go
local io = { input = stdio and stdio.input, output = stdio and stdio.output }
local pid, err = k.process.spawn(function()
  local ok, rc = pcall(shell.withIO, io, shell.execute, line)
  if ok then return rc end
  if rc == "__exit__" then return shell.exitCode or 0 end
  error(rc, 0)
end, { name = line })
if not pid then shell.err("timeout", err); return 125 end

local deadline = computer.uptime() + secs
local ok, res = pcall(function()
  while (k.process.info(pid) or {}).state == "running" do
    local left = deadline - computer.uptime()
    if left <= 0 then return "late" end
    k.event.pull(math.min(left, 0.25))
  end
end)
if not ok or res == "late" then
  k.process.kill(pid)
  if not ok then error(res, 0) end -- Ctrl+C: the shell says ^C
  return 124
end
local info = k.process.info(pid) or {}
if info.state == "failed" then shell.err("timeout", tostring(info.result)); return 1 end
if info.state == "killed" then return 137 end
return tonumber(info.result) or 0
