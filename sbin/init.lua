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

-- ===== First-boot setup wizard (Rufus / archinstall-TUI style) =====
local INSTALLED_MARKER = "/etc/.installed"

local gpu = term.gpu
local W, H = term.size()

-- ---- Palette ---------------------------------------------------------------
local COL = {
  bg          = 0x1A1A1A,  -- desktop background
  fg          = 0xFFFFFF,
  win_bg      = 0x2A2A2A,  -- window body
  win_border  = 0x66CCFF,  -- cyan
  title_bg    = 0x66CCFF,
  title_fg    = 0x000000,
  status_bg   = 0x333333,
  status_fg   = 0xCCCCCC,
  item_fg     = 0xDDDDDD,
  sel_bg      = 0x66CCFF,  -- highlighted row
  sel_fg      = 0x000000,
  ok          = 0x55FF55,
  warn        = 0xFFCC55,
  err         = 0xFF5555,
  dim         = 0x888888,
  input_bg    = 0x111111,
  input_fg    = 0xFFFFFF,
}

-- ---- Low-level draw helpers ------------------------------------------------
local function fill(x, y, w, h, ch, fg, bg)
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  gpu.fill(x, y, w, h, ch or " ")
end

local function text(x, y, s, fg, bg)
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  gpu.set(x, y, s)
end

local function clearScreen()
  fill(1, 1, W, H, " ", COL.fg, COL.bg)
end

local function repeatStr(s, n) return string.rep(s, n) end

-- Draw a box with single-line border. Title shown in the top border (Rufus-y).
local function drawBox(x, y, w, h, title)
  fill(x, y, w, h, " ", COL.fg, COL.win_bg)
  -- corners + edges
  gpu.setBackground(COL.win_bg); gpu.setForeground(COL.win_border)
  gpu.set(x,         y,         "┌" .. repeatStr("─", w - 2) .. "┐")
  gpu.set(x,         y + h - 1, "└" .. repeatStr("─", w - 2) .. "┘")
  for i = 1, h - 2 do
    gpu.set(x,         y + i, "│")
    gpu.set(x + w - 1, y + i, "│")
  end
  if title then
    local t = " " .. title .. " "
    local tx = x + math.max(2, math.floor((w - #t) / 2))
    gpu.setBackground(COL.title_bg); gpu.setForeground(COL.title_fg)
    gpu.set(tx, y, t)
  end
end

-- Status / hint bar across the bottom of the screen.
local function statusBar(hint)
  fill(1, H, W, 1, " ", COL.status_fg, COL.status_bg)
  text(2, H, hint or "", COL.status_fg, COL.status_bg)
  -- right-aligned brand
  local brand = "ByteOS Installer"
  text(W - #brand - 1, H, brand, COL.status_fg, COL.status_bg)
end

-- Top banner with the OS title.
local function topBanner()
  fill(1, 1, W, 1, " ", COL.title_fg, COL.title_bg)
  local s = " " .. _G._OSVERSION .. " (" .. _G._OSCODENAME .. ")  ::  Setup "
  text(2, 1, s, COL.title_fg, COL.title_bg)
end

local function frame()
  clearScreen()
  topBanner()
end

-- Centred window helper. Returns x,y,w,h of the inner content area.
local function centeredWindow(w, h, title)
  w = math.min(w, W - 4)
  h = math.min(h, H - 4)
  local x = math.floor((W - w) / 2) + 1
  local y = math.floor((H - h) / 2) + 1
  drawBox(x, y, w, h, title)
  return x + 2, y + 2, w - 4, h - 4
end

-- ---- Input widgets ---------------------------------------------------------

-- Modal menu. items = { {label=..., value=..., hint=...}, ... }
-- Returns the selected item, or nil on Esc.
local function menuBox(title, items, hint, startIdx)
  local sel = startIdx or 1
  local maxLabel = 0
  for _, it in ipairs(items) do if #it.label > maxLabel then maxLabel = #it.label end end
  local w = math.max(40, math.min(W - 6, maxLabel + 8))
  local h = math.min(H - 6, #items + 4)

  local function draw()
    frame()
    statusBar(hint or " ↑/↓: move    Enter: select    Esc: back ")
    local cx, cy, cw, ch = centeredWindow(w, h, title)
    -- viewport
    local view = ch
    local off = math.max(0, sel - view)
    if off > #items - view then off = math.max(0, #items - view) end
    for i = 1, math.min(view, #items) do
      local idx = i + off
      local it = items[idx]
      if not it then break end
      local label = it.label
      local pad = cw - #label
      if pad < 0 then label = label:sub(1, cw); pad = 0 end
      if idx == sel then
        text(cx, cy + i - 1, label .. repeatStr(" ", pad), COL.sel_fg, COL.sel_bg)
      else
        text(cx, cy + i - 1, label .. repeatStr(" ", pad), COL.item_fg, COL.win_bg)
      end
    end
  end

  while true do
    draw()
    local key = term.readKey()
    if key == "up"   then sel = sel > 1 and sel - 1 or #items
    elseif key == "down" then sel = sel < #items and sel + 1 or 1
    elseif key == "home" then sel = 1
    elseif key == "end"  then sel = #items
    elseif key == "enter" then return items[sel], sel
    elseif key == "escape" or key == "interrupt" then return nil
    elseif tonumber(key) then
      local n = tonumber(key)
      if items[n] then sel = n; draw(); return items[sel], sel end
    end
  end
end

-- Modal text input. mask=true for password.
-- Returns the entered string, or nil on Esc.
local function inputBox(title, label, default, mask)
  local buf = default or ""
  local w = math.max(40, math.min(W - 6, #label + 30))
  local h = 7

  local function draw()
    frame()
    statusBar(" Type value    Enter: confirm    Esc: cancel ")
    local cx, cy, cw = centeredWindow(w, h, title)
    text(cx, cy, label, COL.fg, COL.win_bg)
    -- input field
    local fy = cy + 2
    fill(cx, fy, cw, 1, " ", COL.input_fg, COL.input_bg)
    local shown = mask and repeatStr("*", #buf) or buf
    if #shown > cw then shown = shown:sub(-cw) end
    text(cx, fy, shown, COL.input_fg, COL.input_bg)
    -- caret
    text(cx + #shown, fy, "_", COL.input_fg, COL.input_bg)
  end

  while true do
    draw()
    local key = term.readKey()
    if key == "enter" then return buf
    elseif key == "escape" or key == "interrupt" then return nil
    elseif key == "backspace" then if #buf > 0 then buf = buf:sub(1, -2) end
    elseif type(key) == "string" and #key == 1 and key:byte() >= 32 and key:byte() < 127 then
      buf = buf .. key
    end
  end
end

-- Modal password input with confirm. Returns string or nil on cancel.
local function passwordBox(title, label)
  while true do
    local p1 = inputBox(title, label or "Password:", "", true)
    if p1 == nil then return nil end
    if p1 == "" then
      -- nag and re-ask
      local _ = inputBox(title, "Password may not be empty. Press Enter.", "", false)
    else
      local p2 = inputBox(title, "Confirm password:", "", true)
      if p2 == nil then return nil end
      if p1 == p2 then return p1 end
      local _ = inputBox(title, "Passwords did not match. Press Enter to retry.", "", false)
    end
  end
end

-- Yes/No confirmation. Returns boolean (Esc = false).
local function confirmBox(title, message)
  local items = {
    { label = "  Yes  ", value = true  },
    { label = "  No   ", value = false },
  }
  local sel = 2
  local lines = {}
  for line in (message .. "\n"):gmatch("([^\n]*)\n") do lines[#lines+1] = line end
  local w = math.max(40, math.min(W - 6, 0))
  for _, l in ipairs(lines) do if #l + 6 > w then w = math.min(W - 6, #l + 6) end end
  local h = #lines + 6

  local function draw()
    frame()
    statusBar(" ←/→: switch    Enter: confirm    Esc: No ")
    local cx, cy, cw = centeredWindow(w, h, title)
    for i, l in ipairs(lines) do text(cx, cy + i - 1, l, COL.fg, COL.win_bg) end
    local by = cy + #lines + 1
    local bx = cx + math.floor((cw - 18) / 2)
    for i, it in ipairs(items) do
      local fg, bg = COL.item_fg, COL.win_bg
      if i == sel then fg, bg = COL.sel_fg, COL.sel_bg end
      text(bx + (i - 1) * 9, by, it.label, fg, bg)
    end
  end

  while true do
    draw()
    local key = term.readKey()
    if key == "left" or key == "up"   then sel = 1
    elseif key == "right" or key == "down" then sel = 2
    elseif key == "tab" then sel = sel == 1 and 2 or 1
    elseif key == "y" or key == "Y" then return true
    elseif key == "n" or key == "N" then return false
    elseif key == "enter" then return items[sel].value
    elseif key == "escape" or key == "interrupt" then return false
    end
  end
end

-- Progress bar window. cb(setStep) drives it.
local function withProgress(title, steps, cb)
  local w = math.min(W - 6, 60)
  local h = 9
  local total = #steps
  local current = 0
  local statusLine = ""

  local function draw()
    frame()
    statusBar(" Installing... please wait ")
    local cx, cy, cw = centeredWindow(w, h, title)
    text(cx, cy, ("Step %d of %d"):format(math.min(current, total), total), COL.fg, COL.win_bg)
    -- progress bar
    local by = cy + 2
    local bw = cw
    fill(cx, by, bw, 1, "░", COL.dim, COL.win_bg)
    local filled = math.floor(bw * current / total + 0.5)
    if filled > 0 then fill(cx, by, filled, 1, "█", COL.ok, COL.win_bg) end
    -- percent
    local pct = math.floor(100 * current / total + 0.5)
    text(cx, by + 1, ("%3d%%"):format(pct), COL.fg, COL.win_bg)
    -- current step description
    text(cx, cy + 5, statusLine .. repeatStr(" ", math.max(0, cw - #statusLine)),
         COL.dim, COL.win_bg)
  end

  draw()
  cb(function(stepDescription, stepFn)
    current = current + 1
    statusLine = stepDescription
    draw()
    if stepFn then stepFn() end
    -- tiny pause so the user can watch the bar fill (looks juicier)
    k.event.pull(0.15)
    draw()
  end, steps)
  -- final paint at 100%
  current = total
  statusLine = "done."
  draw()
  k.event.pull(0.4)
end

-- Centred message screen. Press Enter to continue.
local function pressEnter(title, lines)
  local w = 0
  for _, l in ipairs(lines) do if #l > w then w = #l end end
  w = math.max(40, math.min(W - 6, w + 6))
  local h = #lines + 5
  frame()
  statusBar(" Press Enter to continue ")
  local cx, cy = centeredWindow(w, h, title)
  for i, l in ipairs(lines) do text(cx, cy + i - 1, l, COL.fg, COL.win_bg) end
  text(cx, cy + #lines + 1, "[ Press Enter ]", COL.sel_fg, COL.sel_bg)
  while true do
    local key = term.readKey()
    if key == "enter" or key == "escape" then return end
  end
end

-- ---- Wizard state ----------------------------------------------------------

local function runSetup()
  local cfg = {
    hostname = "byteos",
    keymap   = "us",
    locale   = "en_US.UTF-8",
    timezone = "UTC",
    rootpw   = nil,
    user     = nil,
    userpw   = nil,
    wheel    = true,
  }

  -- Welcome
  pressEnter("Welcome to ByteOS",
    {
      "",
      "  This wizard will configure your new ByteOS installation.",
      "",
      "  Use arrow keys (or 1-9) to navigate, Enter to confirm,",
      "  and Esc to go back.",
      "",
    })

  local function pickKeymap()
    local choices = { "us", "de", "fr", "uk", "es", "it", "dvorak" }
    local items = {}
    for _, c in ipairs(choices) do items[#items+1] = { label = c, value = c } end
    local r = menuBox("Keyboard layout", items, " Choose your keyboard layout ")
    if r then cfg.keymap = r.value end
  end

  local function pickLocale()
    local choices = { "en_US.UTF-8", "en_GB.UTF-8", "de_DE.UTF-8", "fr_FR.UTF-8", "C" }
    local items = {}
    for _, c in ipairs(choices) do items[#items+1] = { label = c, value = c } end
    local r = menuBox("Locale", items, " Choose your system locale ")
    if r then cfg.locale = r.value end
  end

  local function pickTimezone()
    local choices = {
      "UTC", "Europe/Berlin", "Europe/London", "Europe/Paris",
      "America/New_York", "America/Los_Angeles", "Asia/Tokyo",
    }
    local items = {}
    for _, c in ipairs(choices) do items[#items+1] = { label = c, value = c } end
    local r = menuBox("Timezone", items, " Choose your timezone ")
    if r then cfg.timezone = r.value end
  end

  local function setHostname()
    local v = inputBox("Hostname", "Hostname (letters, digits, - and _):", cfg.hostname, false)
    if v and v:match("^[%w%-_]+$") then cfg.hostname = v end
  end

  local function setRootPw()
    local v = passwordBox("Root password", "Enter the new root password:")
    if v then cfg.rootpw = v end
  end

  local function setUser()
    local items = {
      { label = "Create a regular user account", value = "create" },
      { label = "Skip (root only)",              value = "skip"   },
    }
    local r = menuBox("User account", items, " ")
    if not r then return end
    if r.value == "skip" then
      cfg.user, cfg.userpw, cfg.wheel = nil, nil, false
      return
    end
    local name = inputBox("User account", "Username:", cfg.user or "user", false)
    if not name or not name:match("^[%w_][%w_-]*$") or name == "root" then return end
    local pw = passwordBox("User account", "Password for " .. name .. ":")
    if not pw then return end
    local wheel = confirmBox("User account",
      "Add '" .. name .. "' to the wheel group (sudoers)?")
    cfg.user, cfg.userpw, cfg.wheel = name, pw, wheel
  end

  -- Main "Rufus-style" overview menu
  while true do
    local function row(label, value, ok)
      local marker = ok and "[✓]" or "[ ]"
      local right  = value or "<not set>"
      local pad    = math.max(1, 50 - #label - #marker - #right - 2)
      return marker .. " " .. label .. repeatStr(" ", pad) .. right
    end

    local items = {
      { label = row("Hostname",        cfg.hostname,                 cfg.hostname ~= ""),  key = "host" },
      { label = row("Keyboard layout", cfg.keymap,                   true),                key = "kb"   },
      { label = row("Locale",          cfg.locale,                   true),                key = "loc"  },
      { label = row("Timezone",        cfg.timezone,                 true),                key = "tz"   },
      { label = row("Root password",   cfg.rootpw and "configured" or "not set",
                                                                     cfg.rootpw ~= nil),   key = "root" },
      { label = row("User account",    cfg.user and (cfg.user .. (cfg.wheel and " (wheel)" or "")) or "skip",
                                                                     cfg.user ~= nil or true),
                                                                                           key = "user" },
      { label = repeatStr("─", 50),                                                        key = "sep"  },
      { label = "  Install ByteOS",                                                        key = "go"   },
      { label = "  Abort and reboot",                                                      key = "abort"},
    }

    local pick = menuBox("ByteOS Setup  -  Main Menu", items,
      " ↑/↓: select   Enter: open   Esc: abort ")
    if not pick or pick.key == "abort" then
      if confirmBox("Abort", "Reboot without installing?") then
        computer.shutdown(true)
      end
    elseif pick.key == "host" then setHostname()
    elseif pick.key == "kb"   then pickKeymap()
    elseif pick.key == "loc"  then pickLocale()
    elseif pick.key == "tz"   then pickTimezone()
    elseif pick.key == "root" then setRootPw()
    elseif pick.key == "user" then setUser()
    elseif pick.key == "go" then
      if not cfg.rootpw then
        pressEnter("Missing setting",
          { "", "  You must set a root password before installing.", "" })
      elseif confirmBox("Confirm",
        "Apply the configuration above and install ByteOS?") then
        break
      end
    end
  end

  -- ---- Apply ---------------------------------------------------------------
  local hn = cfg.hostname

  withProgress("Installing ByteOS",
    {
      "Synchronizing core",
      "Synchronizing extra",
      "Installing bytekernel (1.0.0)",
      "Installing coreutils  (1.0.0)",
      "Installing pacman     (1.0.0)",
      "Installing byteshell  (1.0.0)",
      "Writing /etc/hostname",
      "Writing /etc/vconsole.conf",
      "Writing /etc/locale.conf",
      "Writing /etc/timezone",
      "Writing /etc/hosts",
      "Creating user accounts",
      "Finalizing",
    },
    function(step, steps)
      step("Synchronizing core")
      step("Synchronizing extra")
      step("Installing bytekernel (1.0.0)")
      step("Installing coreutils (1.0.0)")
      step("Installing pacman (1.0.0)")
      step("Installing byteshell (1.0.0)")

      step("Writing /etc/hostname", function()
        fs.writeAll("/etc/hostname", hn .. "\n") end)
      step("Writing /etc/vconsole.conf", function()
        fs.writeAll("/etc/vconsole.conf", "KEYMAP=" .. cfg.keymap .. "\n") end)
      step("Writing /etc/locale.conf", function()
        fs.writeAll("/etc/locale.conf", "LANG=" .. cfg.locale .. "\n") end)
      step("Writing /etc/timezone", function()
        fs.writeAll("/etc/timezone", cfg.timezone .. "\n") end)
      step("Writing /etc/hosts", function()
        fs.writeAll("/etc/hosts",
          "127.0.0.1\tlocalhost\n" ..
          "::1\t\tlocalhost\n" ..
          "127.0.1.1\t" .. hn .. ".localdomain\t" .. hn .. "\n")
      end)

      step("Creating user accounts", function()
        local passwd = { "root:x:0:0:root:/home/root:/bin/sh" }
        local shadow = { "root:" .. cfg.rootpw .. ":::::::" }
        local group  = {
          "root:x:0:root",
          "wheel:x:10:" .. ((cfg.user and cfg.wheel) and cfg.user or ""),
          "users:x:100:",
        }
        if cfg.user then
          table.insert(passwd,
            ("%s:x:1000:1000:%s:/home/%s:/bin/sh"):format(cfg.user, cfg.user, cfg.user))
          table.insert(shadow, ("%s:%s:::::::"):format(cfg.user, cfg.userpw))
          if not fs.exists("/home/" .. cfg.user) then
            fs.makeDirectory("/home/" .. cfg.user)
          end
        end
        fs.writeAll("/etc/passwd", table.concat(passwd, "\n") .. "\n")
        fs.writeAll("/etc/shadow", table.concat(shadow, "\n") .. "\n")
        fs.writeAll("/etc/group",  table.concat(group,  "\n") .. "\n")
      end)

      step("Finalizing", function()
        fs.writeAll(INSTALLED_MARKER,
          "# ByteOS install marker\n" ..
          "HOST=" .. hn .. "\n")
      end)
    end)

  hostname    = hn
  _G.HOSTNAME = hn

  pressEnter("Installation complete",
    {
      "",
      "  ByteOS has been installed successfully.",
      "",
      "  Hostname: " .. hn,
      "  User:     " .. (cfg.user or "root only"),
      "",
      "  Press Enter to continue to the login prompt.",
      "",
    })

  -- restore plain text mode for the login prompt
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  term.clear()
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
  local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
  while true do
    term.write("\n")
    term.write(hostname .. " login: ")
    local user = trim(term.read())
    if user == "" then user = "root" end
    term.write("Password: ")
    local pw = term.read({ mask = "*" }) or ""

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
    term.setForeground(0xFF5555)
    term.write("Login incorrect\n")
    term.setForeground(0xFFFFFF)
  end
end

local user = login()

-- Run the shell forever
while true do
  local ok, err = pcall(shell.repl)
  if not ok then term.write("shell crashed: " .. tostring(err) .. "\n") end
end
