--[[
  sudo - run a command as root

    sudo <command> [args...]
    sudo -k              forget the remembered password right away

  Only members of the wheel group may use it. The password is the user's
  own and is remembered for 5 minutes, like Arch's default
  timestamp_timeout; three wrong passwords end the attempt. The checks
  happen in the kernel (kernel.sudo), which may read /etc/shadow.
]]--

local args = arg or {}
local T    = term.theme

local function fail(msg)
  term.cwrite(T.err, "sudo: ")
  term.cwrite(T.fg, msg .. "\n")
  return 1
end

if args[1] == "-k" then
  k.sudoForget()
  return 0
end
if #args == 0 or args[1] == "-h" or args[1] == "--help" then
  term.write("usage: sudo <command> [args...]\n       sudo -k\n")
  return #args == 0 and 1 or 0
end

-- Rebuild the command line, quoting arguments with spaces the way the shell's
-- tokenizer understands (it has quotes but no backslash escapes).
local line = {}
for i, a in ipairs(args) do
  if not a:find("[%s\"']") then line[i] = a
  elseif not a:find('"', 1, true) then line[i] = '"' .. a .. '"'
  else line[i] = "'" .. a .. "'" end
end
line = table.concat(line, " ")

local user = k.user()
local password
for attempt = 1, 3 do
  if k.sudoNeedsPassword() then
    term.write("[sudo] password for " .. user .. ": ")
    password = term.read({ mask = "•" })
    if password == nil then term.write("\n"); return 1 end
  end
  local ok, rc = k.sudo(password, function()
    k.log(("%s : PWD=%s ; USER=root ; COMMAND=%s"):format(user, tostring(_G.PWD), line), "sudo")
    return shell.execute(line)
  end)
  if ok then return rc end
  if rc == "notsudoer" then
    k.log(user .. " : user NOT in sudoers ; COMMAND=" .. line, "sudo")
    return fail(user .. " is not in the sudoers file. This incident will be reported.")
  end
  if attempt < 3 then term.write("Sorry, try again.\n") end
end
k.log(user .. " : 3 incorrect password attempts ; COMMAND=" .. line, "sudo")
return fail("3 incorrect password attempts")
