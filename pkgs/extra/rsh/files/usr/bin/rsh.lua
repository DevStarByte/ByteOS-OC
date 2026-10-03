--[[
  rsh [user@]host [command ...] - a shell on another computer

  Runs the command on host (a name from netscan or an address) as user
  (default: you) and prints what it printed; rsh ends with its status.
  Without a command you get a prompt there until you type exit.

  The other computer needs the rsh package too (its rshd answers). Each
  command runs on its own there and cannot read the keyboard; cd is
  remembered between commands. The password crosses the network as it
  is, so use rsh only on networks you trust.

    rsh server uptime
    rsh alice@server
]]--
local net = require("net")
local T = term.theme
local args = arg or {}
local target = args[1]
if not target then term.write("usage: rsh [user@]host [command ...]\n"); return 1 end
local user, host = target:match("^([^@]+)@(.+)$")
user, host = user or k.user(), host or target
local line = #args > 1 and table.concat(args, " ", 2) or nil

local addr, name = net.resolve(host)
if not addr then term.cwrite(T.err, "rsh: "); term.write(tostring(name) .. "\n"); return 1 end
name = name or host

term.write(user .. "@" .. name .. "'s password: ")
local password = term.read({ mask = "•" })
if not password then term.write("\n"); return 1 end

-- run one line there (nil: only check the password); ok, status | reason, pwd
local function remote(cmd, cwd, timeout)
  local id = net.newId()
  local sent, err = net.send(addr, "rsh", id, user, password, cwd, cmd)
  if not sent then return nil, err end
  local deadline = computer.uptime() + (timeout or 150)
  while true do
    local left = deadline - computer.uptime()
    if left <= 0 then return nil, "no answer from " .. name end
    local sig = table.pack(k.event.pull(left, "modem_message"))
    if sig[1] == "modem_message" and sig[3] == addr and sig[4] == net.PORT and sig[6] == net.MAGIC and sig[8] == id then
      if sig[7] == "rsh-out" then term.write(tostring(sig[9]))
      elseif sig[7] == "rsh-reply" then return sig[9], sig[10], sig[11] end
    end
  end
end

if line then
  local ok, status = remote(line)
  if not ok then term.cwrite(T.err, "rsh: "); term.write(tostring(status) .. "\n"); return 1 end
  return tonumber(status) or 0
end

local ok, status, cwd = remote(nil, nil, 5)
if not ok then term.cwrite(T.err, "rsh: "); term.write(tostring(status) .. "\n"); return 1 end
term.cwrite(T.muted, "Connected to " .. name .. ". Type exit to leave.\n")
local history = {}
while true do
  term.cwrite(T.green, user .. "@" .. name)
  term.cwrite(T.fg, ":")
  term.cwrite(T.blue, tostring(cwd))
  term.cwrite(T.fg, "$ ")
  local input = term.read({ history = history })
  if not input then term.write("\n"); break end
  input = input:gsub("^%s+", ""):gsub("%s+$", "")
  if input == "exit" or input == "logout" then break end
  if input ~= "" then
    local done, rc, pwd = remote(input, cwd)
    if not done then
      term.cwrite(T.err, "rsh: "); term.write(tostring(rc) .. "\n")
      if rc == "Permission denied" then return 1 end
    else
      cwd = pwd or cwd
    end
  end
end
term.cwrite(T.muted, "Connection to " .. name .. " closed.\n")
return 0
