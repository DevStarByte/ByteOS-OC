--[[
  rshd - lets rsh run commands on this computer (a service)

  Every request carries a user name and password; a command runs as that
  user, in a process of its own, and what it prints goes back. A wrong
  password makes rshd ignore that computer for a few seconds. A command
  that is still running after two minutes is stopped; it cannot read the
  keyboard here.
]]--
local net = require("net")
local MAX_OUTPUT, CHUNK, LIMIT, PENALTY = 65536, 4096, 120, 3
local blocked = {} -- address -> uptime until which it is ignored

local function reply(to, id, buf, ok, status, pwd)
  local out = table.concat(buf)
  if #out > MAX_OUTPUT then out = out:sub(1, MAX_OUTPUT) .. "\n[rsh: output cut at 64 KiB]\n" end
  for i = 1, #out, CHUNK do net.send(to, "rsh-out", id, out:sub(i, i + CHUNK - 1)) end
  net.send(to, "rsh-reply", id, ok, status, pwd)
end

local function handle(from, id, user, password, cwd, line)
  if (blocked[from] or 0) > computer.uptime() then
    return net.send(from, "rsh-reply", id, false, "too many wrong passwords, wait a moment")
  end
  if type(user) ~= "string" or type(password) ~= "string" or not k.checkPassword(user, password) then
    blocked[from] = computer.uptime() + PENALTY
    print(("refused %s from %s"):format(tostring(user), from:sub(1, 8)))
    return net.send(from, "rsh-reply", id, false, "Permission denied")
  end
  if line == nil then -- just a login check: answer with the home directory
    local u = require("auth").user(fs, user)
    return net.send(from, "rsh-reply", id, true, 0, u and u.home or "/")
  end
  print(("%s from %s: %s"):format(user, from:sub(1, 8), tostring(line)))
  local buf, pwd = {}, nil
  local pid, err = k.process.spawn(function()
    shell.setErrorSink(function(t) buf[#buf + 1] = t end)
    if type(cwd) == "string" and fs.isDirectory(cwd) then _G.PWD = cwd end
    local rc = shell.withIO({ output = buf }, shell.execute, tostring(line))
    pwd = _G.PWD
    return rc
  end, { name = "rsh: " .. user, user = user, onexit = function(p)
    if p.state == "done" then reply(from, id, buf, true, tonumber(p.result) or 0, pwd)
    elseif p.state == "killed" then buf[#buf + 1] = "rsh: stopped after " .. LIMIT .. " seconds\n"; reply(from, id, buf, true, 124, cwd)
    else buf[#buf + 1] = "rsh: " .. tostring(p.result) .. "\n"; reply(from, id, buf, true, 1, cwd) end
  end })
  if not pid then return net.send(from, "rsh-reply", id, false, tostring(err)) end
  k.process.spawn(function()
    k.event.pull(LIMIT)
    local info = k.process.info(pid)
    if info and info.state == "running" then k.process.kill(pid) end
  end, { name = "rsh watchdog" })
end

while not net.card() do k.event.pull(30, "component_added") end
print("listening on port " .. net.PORT)
while true do
  local sig = table.pack(k.event.pull(math.huge, "modem_message"))
  if sig[4] == net.PORT and sig[6] == net.MAGIC and sig[7] == "rsh" then
    local ok, err = pcall(handle, sig[3], sig[8], table.unpack(sig, 9, sig.n))
    if not ok then print("error: " .. tostring(err)) end
  end
end
