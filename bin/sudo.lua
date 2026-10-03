--[[
  sudo - run a command as root

    sudo <command> [args...]
    sudo -k              forget the remembered password right away

  Only members of the wheel group (/etc/group) may use it. The password is
  the user's own (/etc/shadow) and is remembered for 5 minutes, like Arch's
  default timestamp_timeout. Three wrong passwords end the attempt.
]]--

local args = arg or {}
local T    = term.theme
local TIMEOUT = 300 -- seconds a correct password is remembered

local function fail(msg)
  term.cwrite(T.err, "sudo: ")
  term.cwrite(T.fg, msg .. "\n")
  return 1
end

local user = _G.USER or "root"
_G.SUDO_TIMESTAMPS = _G.SUDO_TIMESTAMPS or {}
local stamps = _G.SUDO_TIMESTAMPS

if args[1] == "-k" then
  stamps[user] = nil
  return 0
end
if #args == 0 or args[1] == "-h" or args[1] == "--help" then
  term.write("usage: sudo <command> [args...]\n       sudo -k\n")
  return #args == 0 and 1 or 0
end

local function inWheel(name)
  for line in (fs.readAll("/etc/group") or ""):gmatch("[^\r\n]+") do
    local group, members = line:match("^([^:]*):[^:]*:[^:]*:(.*)$")
    if group == "wheel" then
      for m in members:gmatch("[^,%s]+") do
        if m == name then return true end
      end
    end
  end
  return false
end

local function password(name)
  for line in (fs.readAll("/etc/shadow") or ""):gmatch("[^\r\n]+") do
    local n, p = line:match("^([^:]*):([^:]*)")
    if n == name then return p end
  end
end

if user ~= "root" then
  if not inWheel(user) then
    return fail(user .. " is not in the sudoers file. This incident will be reported.")
  end
  local last = stamps[user]
  if not last or computer.uptime() - last > TIMEOUT then
    local stored = password(user)
    local ok = false
    for _ = 1, 3 do
      term.write("[sudo] password for " .. user .. ": ")
      local pw = term.read({ mask = "•" })
      if pw == nil then term.write("\n"); return 1 end
      if stored and pw == stored then ok = true; break end
      term.write("Sorry, try again.\n")
    end
    if not ok then return fail("3 incorrect password attempts") end
  end
  stamps[user] = computer.uptime()
end

-- Rebuild the command line, quoting arguments with spaces the way the shell's
-- tokenizer understands (it has quotes but no backslash escapes).
local line = {}
for i, a in ipairs(args) do
  if not a:find("[%s\"']") then line[i] = a
  elseif not a:find('"', 1, true) then line[i] = '"' .. a .. '"'
  else line[i] = "'" .. a .. "'" end
end

-- Run the command as root; USER is restored even if it fails.
_G.USER = "root"
local ok, rc = pcall(shell.execute, table.concat(line, " "))
_G.USER = user
if not ok then
  if rc == "__logout__" then error(rc, 0) end
  return fail(tostring(rc))
end
return rc
