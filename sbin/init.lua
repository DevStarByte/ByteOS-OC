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
term.write(_G._OSVERSION .. " (" .. _G._OSCODENAME .. ") (tty1)\n")

-- ===== First-boot setup wizard (Arch-flavoured, archinstall-ish) =====
local INSTALLED_MARKER = "/etc/.installed"

-- Arch pacman colours
local C_RESET   = 0xFFFFFF
local C_ARROW   = 0x55FF55  -- bright green "==>"
local C_SUB     = 0x66CCFF  -- cyan "  ->"
local C_WARN    = 0xFFCC55  -- yellow
local C_ERR     = 0xFF5555  -- red
local C_DIM     = 0x999999

local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function cwrite(color, s)
  term.setForeground(color); term.write(s); term.setForeground(C_RESET)
end

local function arrow(msg)        cwrite(C_ARROW, "==> "); term.write(msg .. "\n") end
local function subarrow(msg)     cwrite(C_SUB,   "  -> "); term.write(msg .. "\n") end
local function warn(msg)         cwrite(C_WARN,  "==> WARNING: "); term.write(msg .. "\n") end
local function err_(msg)         cwrite(C_ERR,   "==> ERROR: ");   term.write(msg .. "\n") end

local function prompt(label, default, validate)
  while true do
    cwrite(C_ARROW, "==> ")
    term.write(label)
    if default then cwrite(C_DIM, " [" .. default .. "]") end
    term.write(": ")
    local v = trim(term.read())
    if v == "" and default then v = default end
    if not validate or validate(v) then return v end
    err_("invalid value, try again.")
  end
end

local function promptChoice(label, choices, default)
  arrow(label)
  for i, c in ipairs(choices) do
    cwrite(C_DIM, ("    %2d) "):format(i)); term.write(c .. "\n")
  end
  while true do
    cwrite(C_SUB, "  -> ")
    term.write("choice")
    if default then cwrite(C_DIM, " [" .. default .. "]") end
    term.write(": ")
    local v = trim(term.read())
    if v == "" and default then v = default end
    local n = tonumber(v)
    if n and choices[n] then return choices[n] end
    -- accept the literal name too
    for _, c in ipairs(choices) do if c == v then return c end end
    err_("pick a number from the list.")
  end
end

local function promptYesNo(label, default)
  local d = default and "Y/n" or "y/N"
  while true do
    cwrite(C_ARROW, "==> "); term.write(label .. " [" .. d .. "]: ")
    local v = trim(term.read()):lower()
    if v == "" then return default end
    if v == "y" or v == "yes" then return true  end
    if v == "n" or v == "no"  then return false end
  end
end

local function promptPassword(label)
  while true do
    cwrite(C_ARROW, "==> "); term.write((label or "Password") .. ": ")
    local p1 = term.read({ mask = "*" }) or ""
    cwrite(C_SUB, "  -> "); term.write("Confirm: ")
    local p2 = term.read({ mask = "*" }) or ""
    if p1 == "" then
      err_("password may not be empty.")
    elseif p1 ~= p2 then
      err_("passwords do not match.")
    else
      return p1
    end
  end
end

local function pacstrapStep(pkg, ver)
  cwrite(C_ARROW, ":: ")
  term.write(("installing %s (%s)..."):format(pkg, ver))
  term.write(" ")
  cwrite(C_ARROW, "done\n")
end

local function runSetup()
  term.clear()
  term.setForeground(C_ARROW)
  term.write("   ____        _        ___  ____\n")
  term.write("  | __ ) _   _| |_ ___ / _ \\/ ___|\n")
  term.write("  |  _ \\| | | | __/ _ \\ | | \\___ \\\n")
  term.write("  | |_) | |_| | ||  __/ |_| |___) |\n")
  term.write("  |____/ \\__, |\\__\\___|\\___/|____/\n")
  term.write("         |___/\n")
  term.setForeground(C_RESET)
  term.write("\n")
  cwrite(C_DIM, "  ByteOS Installer  ::  ")
  term.write(_G._OSVERSION .. " (" .. _G._OSCODENAME .. ")\n\n")
  arrow("No system configured. Starting first-boot setup.")
  term.write("\n")

  -- ---- Locale / keymap / timezone (stored as config; mostly cosmetic) ----
  local keymap = promptChoice("Select keyboard layout",
    { "us", "de", "fr", "uk", "es", "it", "dvorak" }, "1")

  local locale = promptChoice("Select locale",
    { "en_US.UTF-8", "en_GB.UTF-8", "de_DE.UTF-8", "fr_FR.UTF-8", "C" }, "1")

  local tz = promptChoice("Select timezone",
    { "UTC", "Europe/Berlin", "Europe/London", "America/New_York",
      "America/Los_Angeles", "Asia/Tokyo" }, "1")

  -- ---- Hostname ----
  local hn = prompt("Hostname", "byteos", function(s)
    return s:match("^[%w%-_]+$") ~= nil
  end)

  -- ---- Root password ----
  arrow("Set the root password")
  local rootpw = promptPassword("Root password")

  -- ---- Optional admin user ----
  local makeUser = promptYesNo("Create an additional user account?", true)
  local un, upw, wheel
  if makeUser then
    un = prompt("Username", "user", function(s)
      return s:match("^[%w_][%w_-]*$") ~= nil and s ~= "root"
    end)
    upw   = promptPassword("Password for " .. un)
    wheel = promptYesNo("Add " .. un .. " to the wheel group (sudoers)?", true)
  end

  -- ---- Confirm ----
  term.write("\n")
  arrow("Configuration summary")
  subarrow("hostname = " .. hn)
  subarrow("keymap   = " .. keymap)
  subarrow("locale   = " .. locale)
  subarrow("timezone = " .. tz)
  subarrow("root     = configured")
  if un then
    subarrow("user     = " .. un .. (wheel and "  (wheel)" or ""))
  else
    subarrow("user     = none")
  end
  term.write("\n")
  if not promptYesNo("Apply these settings?", true) then
    err_("aborted by user. Rebooting in 3s...")
    k.event.pull(3); computer.shutdown(true); return
  end

  -- ---- Apply ----
  term.write("\n")
  arrow("Synchronizing package databases...")
  subarrow("core is up to date")
  subarrow("extra is up to date")

  arrow("Installing base system (pacstrap-style)")
  pacstrapStep("bytekernel", "1.0.0")
  pacstrapStep("coreutils",  "1.0.0")
  pacstrapStep("pacman",     "1.0.0")
  pacstrapStep("byteshell",  "1.0.0")

  arrow("Generating /etc configuration")
  fs.writeAll("/etc/hostname",     hn .. "\n")
  fs.writeAll("/etc/vconsole.conf", "KEYMAP=" .. keymap .. "\n")
  fs.writeAll("/etc/locale.conf",   "LANG=" .. locale .. "\n")
  fs.writeAll("/etc/timezone",      tz .. "\n")
  subarrow("/etc/hostname")
  subarrow("/etc/vconsole.conf")
  subarrow("/etc/locale.conf")
  subarrow("/etc/timezone")

  -- /etc/hosts (Arch's default)
  fs.writeAll("/etc/hosts",
    "127.0.0.1\tlocalhost\n" ..
    "::1\t\tlocalhost\n" ..
    "127.0.1.1\t" .. hn .. ".localdomain\t" .. hn .. "\n")
  subarrow("/etc/hosts")

  -- /etc/passwd + /etc/group + /etc/shadow-ish
  arrow("Creating user accounts")
  local passwd = { ("root:x:0:0:root:/home/root:/bin/sh") }
  local shadow = { ("root:" .. rootpw .. ":::::::") }
  local group  = { "root:x:0:root", "wheel:x:10:" .. (wheel and un or ""), "users:x:100:" }
  if un then
    table.insert(passwd, ("%s:x:1000:1000:%s:/home/%s:/bin/sh"):format(un, un, un))
    table.insert(shadow, ("%s:%s:::::::"):format(un, upw))
    if not fs.exists("/home/" .. un) then fs.makeDirectory("/home/" .. un) end
    subarrow("user '" .. un .. "' created" .. (wheel and " (wheel)" or ""))
  end
  fs.writeAll("/etc/passwd", table.concat(passwd, "\n") .. "\n")
  fs.writeAll("/etc/shadow", table.concat(shadow, "\n") .. "\n")
  fs.writeAll("/etc/group",  table.concat(group,  "\n") .. "\n")
  subarrow("/etc/passwd, /etc/shadow, /etc/group written")

  -- Marker
  fs.writeAll(INSTALLED_MARKER,
    "# ByteOS install marker\n" ..
    "DATE=" .. tostring(computer.uptime()) .. "\n" ..
    "HOST=" .. hn .. "\n")

  hostname    = hn
  _G.HOSTNAME = hn

  term.write("\n")
  cwrite(C_ARROW, "==> ")
  term.write("Installation finished. No error reported.\n")
  cwrite(C_DIM, "    You may now log in.\n\n")
end

if not fs.exists(INSTALLED_MARKER) then
  runSetup()
end

-- Helper: look up a user (reads /etc/passwd + /etc/shadow if present)
local function lookupUser(name, password)
  -- shadow first (passwords stored separately, Arch-style)
  local shadowPass
  if fs.exists("/etc/shadow") then
    for line in (fs.readAll("/etc/shadow") or ""):gmatch("[^\n]+") do
      local n, p = line:match("([^:]+):([^:]*)")
      if n == name then shadowPass = p; break end
    end
  end
  for line in (fs.readAll("/etc/passwd") or ""):gmatch("[^\n]+") do
    local n, pw, _, _, _, home, sh = line:match("([^:]+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)")
    if n == name then
      local stored = (pw == "x" or pw == "" or pw == nil) and shadowPass or pw
      if stored == password then
        return { name = n, home = home, shell = sh }
      end
      return nil
    end
  end
  return nil
end

-- Trivial login with password verification (Arch/agetty-ish)
local function login()
  while true do
    term.write("\n")
    term.write(hostname .. " login: ")
    local user = trim(term.read())
    if user == "" then user = "root" end
    term.write("Password: ")
    local pw = term.read({ mask = "" }) or ""

    local entry = lookupUser(user, pw)
    if entry then
      _G.USER  = entry.name
      _G.HOME  = entry.home
      _G.SHELL = entry.shell
      _G.PWD   = entry.home
      term.write("\n")
      term.write("Last login: just now on tty1\n")
      if fs.exists("/etc/motd") then
        term.write(fs.readAll("/etc/motd") .. "\n")
      end
      return entry
    end
    term.setForeground(C_ERR)
    term.write("Login incorrect\n")
    term.setForeground(C_RESET)
  end
end

local user = login()

-- Run the shell forever
while true do
  local ok, err = pcall(shell.repl)
  if not ok then term.write("shell crashed: " .. tostring(err) .. "\n") end
end
