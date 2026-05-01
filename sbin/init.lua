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

-- Trivial login (single user "root")
local function login()
  while true do
    term.write(hostname .. " login: ")
    local user = term.read() or ""
    user = user:gsub("%s+$", "")
    if user == "" then user = "root" end
    -- look up in /etc/passwd
    local entry
    for line in (fs.readAll("/etc/passwd") or ""):gmatch("[^\n]+") do
      local name, _, _, _, _, home, sh = line:match("([^:]+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)")
      if name == user then
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
    term.write("login: unknown user\n")
  end
end

local user = login()

-- Run the shell forever
while true do
  local ok, err = pcall(shell.repl)
  if not ok then term.write("shell crashed: " .. tostring(err) .. "\n") end
end
