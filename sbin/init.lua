--[[
  /sbin/init.lua - ByteOS init (PID 1)
  Mimics a minimal systemd: runs targets, prints status lines, drops to login.
]]--

local k = _G.kernel
local fs = k.fs

local function status(msg, ok, color)
  local tag = ok and "[  OK  ]" or "[FAILED]"
  local c   = ok and 0x55FF55 or 0xFF5555
  _G.kprint(tag .. " " .. msg, color or c)
end

-- Default environment
_G.PATH = "/bin:/usr/bin:/sbin"

-- Read /etc/hostname
local hostname = "byteos"
if fs.exists("/etc/hostname") then
  hostname = (fs.readAll("/etc/hostname") or "byteos"):gsub("%s+$", "")
end
_G.HOSTNAME = hostname

-- Make sure essential dirs exist
for _, d in ipairs({ "/tmp", "/var", "/var/log", "/home", "/home/root", "/run" }) do
  if not fs.exists(d) then fs.makeDirectory(d) end
end
status("Mounted /tmp /var /home /run", true)

-- Load the term library (provides read/print/clear etc.)
local term = require("term")
_G.term = term
status("Loaded terminal driver", true)

-- Load shell library
local shell = require("shell")
_G.shell = shell
status("Loaded ByteShell core", true)

status("Reached target multi-user.target", true)

-- Welcome / MOTD
term.clear()
if fs.exists("/etc/motd") then
  term.write(fs.readAll("/etc/motd") .. "\n")
end
term.write(_G._OSVERSION .. " (tty1)\n\n")

-- ===== First-boot setup wizard =====
local INSTALLED_MARKER = "/etc/.installed"

local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function prompt(label, default, validate)
  while true do
    term.write(label)
    if default then term.write(" [" .. default .. "]") end
    term.write(": ")
    local v = trim(term.read())
    if v == "" and default then v = default end
    if not validate or validate(v) then return v end
    term.write("  invalid value, try again.\n")
  end
end

local function promptPassword()
  while true do
    term.write("Password: ")
    local p1 = term.read({ mask = "*" }) or ""
    term.write("Confirm:  ")
    local p2 = term.read({ mask = "*" }) or ""
    if p1 == "" then
      term.write("  password may not be empty.\n")
    elseif p1 ~= p2 then
      term.write("  passwords do not match.\n")
    else
      return p1
    end
  end
end

local function runSetup()
  term.clear()
  term.setForeground(0x66CCFF)
  term.write("==========================================\n")
  term.write("        ByteOS First-Time Setup\n")
  term.write("==========================================\n")
  term.setForeground(0xFFFFFF)
  term.write("\nNo install detected. Let's configure your system.\n\n")

  local hn = prompt("Hostname", "byteos", function(s)
    return s:match("^[%w%-_]+$") ~= nil
  end)

  local un = prompt("Username", "root", function(s)
    return s:match("^[%w_]+$") ~= nil
  end)

  local pw = promptPassword()

  -- Write hostname
  fs.writeAll("/etc/hostname", hn .. "\n")

  -- Build /etc/passwd: always keep root; add user if different
  local lines = {}
  if un == "root" then
    table.insert(lines, ("root:%s:0:0:root:/home/root:/bin/sh"):format(pw))
  else
    -- root gets the same password by default so the box is usable
    table.insert(lines, ("root:%s:0:0:root:/home/root:/bin/sh"):format(pw))
    table.insert(lines, ("%s:%s:1000:1000:%s:/home/%s:/bin/sh"):format(un, pw, un, un))
    if not fs.exists("/home/" .. un) then fs.makeDirectory("/home/" .. un) end
  end
  fs.writeAll("/etc/passwd", table.concat(lines, "\n") .. "\n")

  -- Mark installed
  fs.writeAll(INSTALLED_MARKER, "1\n")

  hostname = hn
  _G.HOSTNAME = hn

  term.setForeground(0x55FF55)
  term.write("\nSetup complete. You can now log in as '" .. un .. "'.\n\n")
  term.setForeground(0xFFFFFF)
end

if not fs.exists(INSTALLED_MARKER) then
  runSetup()
end

-- Trivial login with password verification
local function login()
  while true do
    term.write(hostname .. " login: ")
    local user = trim(term.read())
    if user == "" then user = "root" end
    term.write("Password: ")
    local pw = term.read({ mask = "*" }) or ""

    local entry
    for line in (fs.readAll("/etc/passwd") or ""):gmatch("[^\n]+") do
      local name, pass, _, _, _, home, sh = line:match("([^:]+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)")
      if name == user and pass == pw then
        entry = { name = name, home = home, shell = sh }
        break
      end
    end
    if entry then
      _G.USER  = entry.name
      _G.HOME  = entry.home
      _G.SHELL = entry.shell
      _G.PWD   = entry.home
      term.write("\nWelcome to " .. _G._OSVERSION .. "\n")
      return entry
    end
    term.write("Login incorrect\n\n")
  end
end

local user = login()

-- Run the shell forever
while true do
  local ok, err = pcall(shell.repl)
  if not ok then term.write("shell crashed: " .. tostring(err) .. "\n") end
end
