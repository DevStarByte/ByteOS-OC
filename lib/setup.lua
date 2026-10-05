--[[
  /lib/setup.lua - the first-boot setup wizard

  /sbin/init runs setup.run() when /etc/.installed is missing: a
  full-screen dialog for hostname, time zone, root password and a user,
  which writes /etc/hostname, /etc/timezone, /etc/passwd, /etc/shadow,
  /etc/group and the /etc/.installed marker. It lives here rather than in
  init so it takes memory only on that first boot.
]]--

local k = _G.kernel
local fs = k.fs
local term = require("term")
local T = term.theme
local W, H = term.size()

local setup = {}

local INSTALLED_MARKER = "/etc/.installed"

local gpu = term.gpu

-- ---- Palette (roles map onto the shared theme) -----------------------------
local COL = {
  desk      = T.base,      -- desktop background
  win       = T.surface,   -- window body
  shadow    = T.bg,
  title_bg  = T.accent,
  title_fg  = T.on_accent,
  bar_bg    = T.raised,    -- top / bottom bars
  bar_fg    = T.fg,
  key       = T.accent,    -- key names in the hint bar
  fg        = T.fg,
  dim       = T.muted,
  sel_bg    = T.accent,
  sel_fg    = T.on_accent,
  input_bg  = T.bg,
  input_fg  = T.bright,
  button    = T.raised,
  ok        = T.ok,
  warn      = T.warn,
  err       = T.err,
  logo      = T.accent,
}
if T.mono then COL.key, COL.logo = T.fg, T.fg end

-- ---- Low-level draw helpers ------------------------------------------------
local function fill(x, y, w, h, ch, fg, bg)
  if w <= 0 or h <= 0 then return end
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  gpu.fill(x, y, w, h, ch or " ")
end

local function text(x, y, s, fg, bg)
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  gpu.set(x, y, s)
end

local function repeatStr(s, n) return string.rep(s, math.max(0, n)) end

-- UTF-8 aware helpers: labels can contain multi-byte glyphs (✓, ─), but
-- Lua's # and :sub() count bytes, not display columns. Layout math (padding,
-- truncation) needs actual column counts or it misaligns / cuts glyphs in half.
local ulen = term.ulen
local function utruncate(s, n) return term.usub(s, 1, n) end

local LOGO = {
  [[ ____        _        ___  ____  ]],
  [[| __ ) _   _| |_ ___ / _ \/ ___| ]],
  [[|  _ \| | | | __/ _ \ | | \___ \ ]],
  [[| |_) | |_| | ||  __/ |_| |___) |]],
  [[|____/ \__, |\__\___|\___/|____/ ]],
  [[       |___/                     ]],
}

-- Bottom bar with key hints. hints = { {"Enter", "select"}, ... }
local function statusBar(hints)
  fill(1, H, W, 1, " ", COL.bar_fg, COL.bar_bg)
  local x = 2
  for _, h in ipairs(hints or {}) do
    local need = ulen(h[1]) + ulen(h[2]) + 3
    if x + need > W then break end
    text(x, H, h[1], COL.key, COL.bar_bg)
    text(x + ulen(h[1]) + 1, H, h[2], COL.dim, COL.bar_bg)
    x = x + need
  end
end

-- Top bar with the OS title.
local function topBanner(step)
  fill(1, 1, W, 1, " ", COL.title_fg, COL.title_bg)
  text(2, 1, "ByteOS Setup", COL.title_fg, COL.title_bg)
  local right = step or (_G._OSVERSION .. " (" .. _G._OSCODENAME .. ")")
  if ulen(right) + 16 < W then
    text(W - ulen(right), 1, right, COL.title_fg, COL.title_bg)
  end
end

local function frame(step)
  fill(1, 1, W, H, " ", COL.fg, COL.desk)
  topBanner(step)
end

-- Window with an accent title bar and a drop shadow (2 columns right,
-- 1 row down: screen cells are roughly twice as tall as they are wide).
local function drawWindow(x, y, w, h, title)
  fill(x + 2, y + 1, w, h, " ", COL.fg, COL.shadow)
  fill(x, y, w, h, " ", COL.fg, COL.win)
  fill(x, y, w, 1, " ", COL.title_fg, COL.title_bg)
  if title then
    local t = utruncate(title, w - 2)
    text(x + math.floor((w - ulen(t)) / 2), y, t, COL.title_fg, COL.title_bg)
  end
  -- Monochrome screens can't tell the window body from the desktop by
  -- colour, so outline it instead.
  if T.mono then
    gpu.setForeground(COL.fg); gpu.setBackground(COL.win)
    for i = 1, h - 2 do
      gpu.set(x, y + i, "│"); gpu.set(x + w - 1, y + i, "│")
    end
    gpu.set(x, y + h - 1, "└" .. repeatStr("─", w - 2) .. "┘")
  end
end

-- Centred window helper. Returns x,y,w,h of the inner content area
-- (one blank row under the title bar, two columns of side padding).
local function centeredWindow(w, h, title)
  w = math.min(w, W - 4)
  h = math.min(h, H - 4)
  local x = math.floor((W - w) / 2) + 1
  local y = math.floor((H - h) / 2) + 1
  drawWindow(x, y, w, h, title)
  return x + 2, y + 2, w - 4, h - 3
end

-- A push-button. Selected buttons are drawn in the accent colour.
local function button(x, y, label, selected)
  local s = "  " .. label .. "  "
  if selected then text(x, y, s, COL.sel_fg, COL.sel_bg)
  else text(x, y, s, COL.fg, COL.button) end
  return ulen(s)
end

-- ---- Input widgets ---------------------------------------------------------

-- Modal menu. items = { {label=..., value=..., right=..., mark=...}, ... }
--   right : optional text right-aligned in the row (muted)
--   mark  : "ok" (green ✓), "todo" (yellow •) or nil (no marker column)
--   sep   : true for a non-selectable separator line
-- Returns the selected item, or nil on Shift+Q / Backspace.
local function menuBox(title, items, hints, startIdx, step)
  local sel = startIdx or 1
  local function selectable(i) return items[i] and not items[i].sep end
  while not selectable(sel) and sel < #items do sel = sel + 1 end

  local hasMarks, maxLabel, maxRight = false, 0, 0
  for _, it in ipairs(items) do
    if it.mark then hasMarks = true end
    maxLabel = math.max(maxLabel, ulen(it.label or ""))
    maxRight = math.max(maxRight, ulen(it.right or ""))
  end
  local need = maxLabel + (maxRight > 0 and maxRight + 3 or 0) + (hasMarks and 2 or 0) + 2
  local w = math.max(36, math.min(W - 6, need + 4))
  local h = math.min(H - 4, #items + 3)

  local function draw()
    frame(step)
    statusBar(hints or { { "↑↓", "move" }, { "Enter", "select" }, { "Shift+Q", "back" } })
    local cx, cy, cw, ch = centeredWindow(w, h, title)
    local view = ch
    local off = math.max(0, sel - view)
    if off > #items - view then off = math.max(0, #items - view) end
    for i = 1, math.min(view, #items) do
      local idx = i + off
      local it = items[idx]
      if not it then break end
      local y = cy + i - 1
      if it.sep then
        text(cx, y, repeatStr("─", cw), T.dim, COL.win)
      else
        local isSel = idx == sel
        local fg, bg = COL.fg, COL.win
        if isSel then fg, bg = COL.sel_fg, COL.sel_bg end
        fill(cx - 1, y, cw + 2, 1, " ", fg, bg)
        local x = cx
        if hasMarks then
          if it.mark == "ok" then text(x, y, "✓", isSel and fg or COL.ok, bg)
          elseif it.mark == "todo" then text(x, y, "•", isSel and fg or COL.warn, bg) end
          x = x + 2
        end
        local right = it.right or ""
        local room = cw - (x - cx) - (right ~= "" and ulen(right) + 1 or 0)
        text(x, y, utruncate(it.label, room), fg, bg)
        if right ~= "" then
          text(cx + cw - ulen(right), y, right, isSel and fg or COL.dim, bg)
        end
      end
    end
    -- scroll indicators
    if off > 0 then text(cx + cw, cy, "▲", COL.dim, COL.win) end
    if off + view < #items then text(cx + cw, cy + view - 1, "▼", COL.dim, COL.win) end
  end

  local function move(d)
    local i = sel
    repeat i = ((i - 1 + d) % #items) + 1 until selectable(i) or i == sel
    sel = i
  end

  while true do
    draw()
    local key = term.readKey()
    if key == "up" then move(-1)
    elseif key == "down" then move(1)
    elseif key == "home" then sel = 0; move(1)
    elseif key == "end" then sel = #items + 1; move(-1)
    elseif key == "enter" then return items[sel], sel
    elseif key == "Q" or key == "backspace" or key == "interrupt" then return nil
    elseif tonumber(key) then
      local n = tonumber(key)
      if selectable(n) then sel = n; draw(); return items[sel], sel end
    end
  end
end

-- Modal text input. mask=true for password.
-- Returns the entered string, or nil if cancelled. `note` is an optional
-- second line shown under the label (e.g. a validation error).
local function inputBox(title, label, default, mask, note, step)
  local buf = default or ""
  local w = math.max(40, math.min(W - 6, ulen(label) + 8, 60))
  local h = note and 8 or 7

  local function draw()
    frame(step)
    statusBar({ { "Enter", "confirm" }, { "Backspace", "erase" }, { "Ctrl+C", "cancel" } })
    local cx, cy, cw = centeredWindow(w, h, title)
    text(cx, cy, utruncate(label, cw), COL.fg, COL.win)
    local fy = cy + 2
    if note then
      text(cx, cy + 1, utruncate(note, cw), COL.warn, COL.win)
      fy = cy + 3
    end
    -- on monochrome screens the field has no colour of its own; underline it
    fill(cx, fy, cw, 1, T.mono and "_" or " ", COL.input_fg, COL.input_bg)
    local shown = mask and repeatStr("•", ulen(buf)) or buf
    if ulen(shown) > cw - 1 then shown = term.usub(shown, -(cw - 1)) end
    text(cx, fy, shown, COL.input_fg, COL.input_bg)
    term.setCursor(cx + ulen(shown), fy)
  end

  while true do
    draw()
    local key, extra = term.readKey(true)
    if key == "enter" then return buf
    elseif key == "interrupt" or key == "ctrl+c" then return nil
    elseif key == "backspace" then
      if ulen(buf) > 0 then buf = term.usub(buf, 1, -2) end
    elseif key == "paste" then
      buf = buf .. ((extra or ""):match("^[^\r\n]*"))
    elseif ulen(key) == 1 then
      buf = buf .. key
    end
  end
end

-- Modal password input with confirm. Returns string or nil on cancel.
local function passwordBox(title, label, step)
  local note
  while true do
    local p1 = inputBox(title, label or "Password:", "", true, note, step)
    if p1 == nil then return nil end
    if p1 == "" then
      note = "The password may not be empty."
    else
      local p2 = inputBox(title, "Confirm password:", "", true, nil, step)
      if p2 == nil then return nil end
      if p1 == p2 then return p1 end
      note = "Passwords did not match, try again."
    end
  end
end

-- Yes/No confirmation. Returns boolean (Shift+Q = false).
local function confirmBox(title, message, default, step)
  local sel = default == true and 1 or 2
  local lines = {}
  for line in (message .. "\n"):gmatch("([^\n]*)\n") do lines[#lines+1] = line end
  local w = 40
  for _, l in ipairs(lines) do w = math.max(w, ulen(l) + 6) end
  w = math.min(W - 6, w)
  local h = #lines + 6

  local function draw()
    frame(step)
    statusBar({ { "←→", "switch" }, { "Y/N", "answer" }, { "Enter", "confirm" } })
    local cx, cy, cw = centeredWindow(w, h, title)
    for i, l in ipairs(lines) do text(cx, cy + i - 1, utruncate(l, cw), COL.fg, COL.win) end
    local by = cy + #lines + 1
    local bx = cx + math.floor((cw - 18) / 2)
    button(bx, by, "Yes", sel == 1)
    button(bx + 10, by, "No ", sel == 2)
  end

  while true do
    draw()
    local key = term.readKey()
    if key == "left" or key == "up" then sel = 1
    elseif key == "right" or key == "down" then sel = 2
    elseif key == "tab" then sel = sel == 1 and 2 or 1
    elseif key == "y" or key == "Y" then return true
    elseif key == "n" or key == "N" then return false
    elseif key == "enter" then return sel == 1
    elseif key == "Q" or key == "interrupt" then return false
    end
  end
end

-- Progress window. cb(step) drives it; each step(description, fn) runs fn
-- and advances the bar. Finished steps are listed above the bar.
local function withProgress(title, steps, cb)
  local w = math.min(W - 6, 60)
  local h = math.min(H - 4, 14)
  local total = #steps
  local done = {}
  local current = 0
  local statusLine = ""

  local function draw()
    frame("Installing")
    statusBar({ { "", "Installing ByteOS, please wait..." } })
    local cx, cy, cw, ch = centeredWindow(w, h, title)
    -- log of finished steps (most recent at the bottom)
    local logRows = math.max(0, ch - 3)
    local first = math.max(1, #done - logRows + 1)
    for i = first, #done do
      local y = cy + (i - first)
      text(cx, y, "✓", COL.ok, COL.win)
      text(cx + 2, y, utruncate(done[i], cw - 2), COL.dim, COL.win)
    end
    -- current step, bar and percentage
    local by = cy + ch - 1
    fill(cx, by - 1, cw, 1, " ", COL.fg, COL.win)
    text(cx, by - 1, utruncate(statusLine, cw - 5), COL.fg, COL.win)
    local pct = math.floor(100 * current / total + 0.5)
    local p = ("%3d%%"):format(pct)
    text(cx + cw - #p, by - 1, p, COL.fg, COL.win)
    local filled = math.floor(cw * current / total + 0.5)
    fill(cx, by, cw, 1, "━", T.dim, COL.win)
    if filled > 0 then fill(cx, by, filled, 1, "━", COL.sel_bg, COL.win) end
  end

  draw()
  cb(function(stepDescription, stepFn)
    statusLine = stepDescription .. "..."
    draw()
    if stepFn then stepFn() end
    current = current + 1
    done[#done + 1] = stepDescription
    -- tiny pause so the user can watch the bar fill
    k.event.pull(0.1)
  end, steps)
  current = total
  statusLine = "Done."
  draw()
  k.event.pull(0.4)
end

-- Centred message window with an OK button. Press Enter to continue.
-- lines may contain { text, color } pairs instead of plain strings.
local function pressEnter(title, lines, step)
  local w = 0
  for _, l in ipairs(lines) do
    w = math.max(w, ulen(type(l) == "table" and l[1] or l))
  end
  w = math.max(40, math.min(W - 6, w + 6))
  local h = #lines + 5
  frame(step)
  statusBar({ { "Enter", "continue" } })
  local cx, cy, cw = centeredWindow(w, h, title)
  for i, l in ipairs(lines) do
    local s, c = l, COL.fg
    if type(l) == "table" then s, c = l[1], l[2] end
    text(cx, cy + i - 1, utruncate(s, cw), c, COL.win)
  end
  button(cx + cw - 6, cy + #lines + 1, "OK", true)
  while true do
    local key = term.readKey()
    if key == "enter" then return end
  end
end

-- ---- Wizard state ----------------------------------------------------------

-- Run the wizard; returns the chosen hostname.
function setup.run()
  local cfg = {
    hostname = "ByteOS",
    timezone = "UTC",
    rootpw   = nil,
    user     = nil,
    userpw   = nil,
    wheel    = true,
  }

  -- Welcome: logo + intro, sized to the screen
  do
    local lines = {}
    if H >= 22 and W >= 50 then
      for _, l in ipairs(LOGO) do lines[#lines + 1] = { l, COL.logo } end
      lines[#lines + 1] = ""
    end
    local intro = {
      "This wizard sets up your new system.",
      "",
      { "↑↓ or 1-9   choose an option", COL.dim },
      { "Enter       confirm", COL.dim },
      { "Shift+Q     go back", COL.dim },
    }
    for _, l in ipairs(intro) do lines[#lines + 1] = l end
    pressEnter("Welcome to ByteOS", lines)
  end

  local function pick(title, choices, current)
    local items, start = {}, 1
    for i, c in ipairs(choices) do
      items[#items+1] = { label = c, value = c }
      if c == current then start = i end
    end
    local r = menuBox(title, items, nil, start, "Settings")
    return r and r.value
  end

  -- the zone applies once timesyncd has the real time from the internet
  local function pickTimezone()
    cfg.timezone = pick("Timezone", require("clock").zones(), cfg.timezone) or cfg.timezone
  end

  local function setHostname()
    local note
    while true do
      local v = inputBox("Hostname", "Name of this computer:", cfg.hostname, false, note, "Settings")
      if not v then return end
      if v:match("^[%w%-_]+$") then cfg.hostname = v; return end
      note = "Use only letters, digits, - and _."
    end
  end

  local function setRootPw()
    local v = passwordBox("Root password", "New password for root:", "Settings")
    if v then cfg.rootpw = v end
  end

  local function setUser()
    local items = {
      { label = "Create a regular user account", value = "create" },
      { label = "Skip (root only)",              value = "skip"   },
    }
    local r = menuBox("User account", items, nil, nil, "Settings")
    if not r then return end
    if r.value == "skip" then
      cfg.user, cfg.userpw, cfg.wheel = nil, nil, false
      return
    end
    local name, note
    while true do
      name = inputBox("User account", "Username:", name or cfg.user or "user", false, note, "Settings")
      if not name then return end
      if name:match("^[%w_][%w_-]*$") and name ~= "root" then break end
      note = name == "root" and "That name is reserved." or "Use letters, digits, - and _."
    end
    local pw = passwordBox("User account", "Password for " .. name .. ":", "Settings")
    if not pw then return end
    local wheel = confirmBox("User account",
      "Allow '" .. name .. "' to use sudo?\n(adds the user to the wheel group)", true, "Settings")
    cfg.user, cfg.userpw, cfg.wheel = name, pw, wheel
  end

  -- Main overview menu
  local last = 1
  while true do
    local items = {
      { label = "Hostname",        right = cfg.hostname, mark = "ok", key = "host" },
      { label = "Timezone",        right = cfg.timezone, mark = "ok", key = "tz"   },
      { label = "Root password",   right = cfg.rootpw and "set" or "required",
        mark = cfg.rootpw and "ok" or "todo", key = "root" },
      { label = "User account",    right = cfg.user and (cfg.user .. (cfg.wheel and " (sudo)" or "")) or "root only",
        mark = "ok", key = "user" },
      { sep = true },
      { label = "Install ByteOS",    key = "go"    },
      { label = "Abort and reboot",  key = "abort" },
    }

    local pick, idx = menuBox("Installation summary", items,
      { { "↑↓", "move" }, { "Enter", "change" }, { "Shift+Q", "abort" } }, last, "Settings")
    last = idx or last
    if not pick or pick.key == "abort" then
      if confirmBox("Abort", "Reboot without installing?") then
        computer.shutdown(true)
      end
    elseif pick.key == "host" then setHostname()
    elseif pick.key == "tz"   then pickTimezone()
    elseif pick.key == "root" then setRootPw()
    elseif pick.key == "user" then setUser()
    elseif pick.key == "go" then
      if not cfg.rootpw then
        pressEnter("Missing setting",
          { { "A root password is required.", COL.warn }, "",
            "Select 'Root password' to set one." })
        last = 3 -- the "Root password" entry
      elseif confirmBox("Ready to install",
        "Write the configuration and install ByteOS?", true) then
        break
      end
    end
  end

  -- ---- Apply ---------------------------------------------------------------
  local hn = cfg.hostname
  local base = "Installing byteos " .. ((_G._OSVERSION or ""):match("[%d%.]+") or "")

  local steps = {
    "Synchronizing core", "Synchronizing extra", base,
    "Writing /etc/hostname", "Writing /etc/timezone",
    "Writing /etc/hosts", "Creating user accounts", "Finalizing",
  }
  withProgress("Installing ByteOS", steps,
    function(step)
      step("Synchronizing core")
      step("Synchronizing extra")
      step(base)

      step("Writing /etc/hostname", function()
        fs.writeAll("/etc/hostname", hn .. "\n") end)
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
        local hash = require("auth").hash
        local shadow = { "root:" .. hash(cfg.rootpw) .. ":::::::" }
        local group  = {
          "root:x:0:root",
          "wheel:x:10:" .. ((cfg.user and cfg.wheel) and cfg.user or ""),
          "users:x:100:",
        }
        if cfg.user then
          table.insert(passwd,
            ("%s:x:1000:100:%s:/home/%s:/bin/sh"):format(cfg.user, cfg.user, cfg.user))
          table.insert(shadow, ("%s:%s:::::::"):format(cfg.user, hash(cfg.userpw)))
          local home = "/home/" .. cfg.user
          if not fs.exists(home) then fs.makeDirectory(home) end
          -- like /etc/skel on Linux: the new user starts with the default dotfiles
          for _, f in ipairs({ ".shrc", ".profile" }) do
            if fs.exists("/etc/skel/" .. f) and not fs.exists(home .. "/" .. f) then
              fs.writeAll(home .. "/" .. f, fs.readAll("/etc/skel/" .. f))
            end
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

  _G.HOSTNAME = hn

  pressEnter("Installation complete",
    {
      { "✓ ByteOS has been installed.", COL.ok },
      "",
      { "Hostname  " .. hn, COL.fg },
      { "Users     root" .. (cfg.user and (", " .. cfg.user) or ""), COL.fg },
      "",
      { "Continue to the login prompt.", COL.dim },
    }, "Done")

  term.clear()
  return hn
end

return setup
