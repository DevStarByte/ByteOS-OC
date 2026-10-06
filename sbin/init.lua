--[[
  /sbin/init.lua - ByteOS init (PID 1)
  Mimics a minimal systemd: runs targets, prints status lines, drops to login.
]]--

local k = _G.kernel
local fs = k.fs

-- Default environment
_G.PATH = "/bin:/usr/bin:/sbin"

-- Load the term library first: it programs the GPU palette, so everything
-- drawn afterwards (including the boot status lines) uses the final colours.
local term = require("term")
_G.term = term
local T = term.theme
local ulen = term.ulen

local function status(msg, kind, quiet)
  local tag, color = "  OK  ", T.ok
  if kind == "fail" then tag, color = "FAILED", T.err
  elseif kind == "info" then tag, color = " INFO ", T.accent
  elseif kind == "warn" then tag, color = " WARN ", T.warn end
  _G.kstatus({ { "[", T.fg }, { tag, color }, { "] ", T.fg }, { msg, T.fg } })
  if not quiet then k.log((kind == "fail" and "FAILED: " or "") .. msg, "init") end
end

-- Read /etc/hostname
local hostname = "byteos"
if fs.exists("/etc/hostname") then
  hostname = (fs.readAll("/etc/hostname") or "byteos"):gsub("%s+$", "")
end
_G.HOSTNAME = hostname

local W, H = term.size()
local tier = ({ [1] = 1, [4] = 2, [8] = 3 })[term.depth] or "?"
status(("Loaded terminal driver (Tier %s GPU, %dx%d, %d-bit colour)."):format(tier, W, H, term.depth))

-- Make sure essential dirs exist
for _, d in ipairs({ "/tmp", "/var", "/var/log", "/home", "/home/root", "/run", "/mnt" }) do
  if not fs.exists(d) then fs.makeDirectory(d) end
end
status("Created runtime directories /tmp /run /var/log /mnt.")

local mounts = k.fs.mounts()
status(("Mounted %d filesystem%s."):format(#mounts, #mounts == 1 and "" or "s"))
status(("Detected %d KiB of memory."):format(math.floor(computer.totalMemory() / 1024)))
if component.list("internet")() then
  status("Found internet card.")
else
  status("No internet card: no online updates, packages or clock sync.", "info")
end

-- Load shell library
local shell = require("shell")
_G.shell = shell
status("Started ByteShell.")
-- Booting this far means a fresh byteos upgrade works; stop init.lua from
-- rolling it back on a later panic.
if fs.exists("/var/lib/pacman/byteos/pending") then
  fs.remove("/var/lib/pacman/byteos/pending")
  status("Finished applying system update.")
end

-- Enabled services (systemctl enable ...) start now, before the login
-- prompt, and keep running in the background. systemd logs them itself.
for _, r in ipairs(require("systemd").boot()) do
  if r.ok then status("Started " .. r.description .. ".", nil, true)
  else status("Failed to start " .. r.description .. ": " .. tostring(r.err), "fail") end
end
status("Reached target Multi-User System.")
k.event.pull(0.5) -- let the boot log be read before it is cleared

-- ===== First-boot setup ======================================================
-- The wizard (lib/setup.lua) is loaded only on the very first boot and let
-- go of afterwards, so it does not take memory for the whole session.
if not fs.exists("/etc/.installed") then
  hostname = require("setup").run()
  package.loaded.setup = nil
end


-- ===== Login ================================================================

-- The account for `name` if `password` is right. The kernel checks the
-- hash in /etc/shadow (and turns an old plain-text password into one).
local function lookupUser(name, password)
  local u = require("auth").user(fs, name)
  if u and k.checkPassword(name, password) then
    return { name = u.name, home = u.home, shell = u.shell }
  end
  return nil
end

-- Expand agetty-style escapes in /etc/issue.
local function expandIssue(s)
  local map = {
    s = "ByteOS", r = (_G._OSVERSION or ""):match("[%d%.]+") or "", n = hostname,
    l = "tty1", m = "lua",
  }
  return (s:gsub("\\(%a)", function(c) return map[c] or ("\\" .. c) end))
end

-- Print banner text (issue / motd). Leading block of lines up to the first
-- blank line after some content is treated as ASCII art and drawn in the
-- accent colour; `backticked` words in the rest are highlighted.
-- With centre=true the whole block is centred horizontally as one unit.
local function printBanner(textBlock, centre)
  local lines = {}
  for l in (textBlock:gsub("\n+$", "") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, ulen(l)) end
  local indent = centre and math.max(0, math.floor((W - width) / 2)) or 0
  local art, seen = true, false
  for _, l in ipairs(lines) do
    if l:match("^%s*$") then
      if seen then art = false end
    else
      seen = true
    end
    term.write(string.rep(" ", indent))
    if art then
      term.cwrite(T.mono and T.fg or T.accent, l)
    else
      local pos = 1
      for pre, code, nxt in l:gmatch("()`([^`]*)`()") do
        term.cwrite(T.fg, l:sub(pos, pre - 1))
        term.cwrite(T.blue, code)
        pos = nxt
      end
      term.cwrite(T.fg, l:sub(pos))
    end
    term.write("\n")
  end
  return indent
end

local function loginScreen(errorMsg)
  term.clear()
  local issue = fs.exists("/etc/issue") and fs.readAll("/etc/issue")
                or (_G._OSVERSION .. " (\\n) \\l\n")
  local lines = select(2, issue:gsub("\n", "")) + 1
  term.setCursor(1, math.max(1, math.floor((H - lines - 6) / 2)))
  term.setForeground(T.muted)
  local indent = printBanner(expandIssue(issue), true)
  term.write("\n")
  if errorMsg then
    term.write(string.rep(" ", indent))
    term.cwrite(T.err, errorMsg)
  end
  term.write("\n")
  return indent
end

-- Remember when each user last logged in (in-game time, when available).
local LASTLOG = "/var/log/lastlog"
local function lastLogin(name)
  local prev
  local entries = {}
  if fs.exists(LASTLOG) then
    for line in (fs.readAll(LASTLOG) or ""):gmatch("[^\n]+") do
      local n, when = line:match("^(%S+)%s+(.+)$")
      if n then entries[n] = when end
    end
  end
  prev = entries[name]
  local ok, now = pcall(os.date, "%a %b %d %H:%M")
  entries[name] = (ok and now) or "earlier"
  local out = {}
  for n, when in pairs(entries) do out[#out + 1] = n .. " " .. when end
  pcall(fs.writeAll, LASTLOG, table.concat(out, "\n") .. "\n")
  return prev
end

-- Login with password verification (Arch/agetty-ish). Returns the account.
local function login()
  local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
  local errorMsg
  while true do
    local indent = loginScreen(errorMsg)
    local pad = string.rep(" ", indent)
    term.write(pad); term.cwrite(T.fg, hostname .. " login: ")
    term.setForeground(T.bright)
    local user = trim(term.read())
    if user == "" then user = "root" end
    term.write(pad); term.cwrite(T.fg, "Password: ")
    local pw = term.read({ mask = "•" }) or ""

    local entry = lookupUser(user, pw)
    if not entry then k.log("FAILED LOGIN for '" .. user .. "'", "login") end
    if entry then
      k.log("session opened for user " .. entry.name, "login")
      _G.USER  = entry.name
      _G.HOME  = entry.home
      _G.SHELL = entry.shell
      _G.PWD   = entry.home
      term.clear()
      local prev = lastLogin(entry.name)
      if prev then term.cwrite(T.muted, "Last login: " .. prev .. " on tty1\n") end
      if fs.exists("/etc/motd") then
        printBanner(fs.readAll("/etc/motd") or "")
        term.write("\n")
      end
      term.setForeground(T.fg)
      return entry
    end
    errorMsg = "Login incorrect"
  end
end

-- Log in, run the shell until the user exits, then return to the login screen.
while true do
  login()
  -- the kernel runs the shell as that user (file permissions, sudo)
  local ok, err = pcall(k.runAs, _G.USER, shell.repl)
  if not ok then
    term.cwrite(T.err, "shell crashed: " .. tostring(err) .. "\n")
    k.event.pull(2)
  end
  k.log("session closed for user " .. tostring(_G.USER), "login")
  -- logged out: nothing of this session carries over to the next user
  _G.USER, _G.HOME, _G.SHELL = nil, nil, nil
  _G.PWD = "/"
end
