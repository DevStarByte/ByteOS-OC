--[[
  hyprbyte - a tiling window manager, in the spirit of Hyprland

  Every window is a terminal with its own shell. New windows split the
  space (dwindle: halves of halves), there are nine workspaces, and a bar
  on top shows them with the window in focus, memory, energy and the time.
  Start it from the shell, or pick the Hyprbyte session at the login (F2).

  Keys (Mod is Alt; mod = super in the config makes it the Windows key):
    Mod+Enter         a new terminal
    Mod+D             run a program in a new window (a launcher)
    Mod+Q             close the window in focus
    Mod+Arrows/Tab    focus the previous / next window
    Mod+Shift+Arrows  move the window in focus back / forward
    Mod+F             full screen on / off
    Mod+1 ... Mod+9   go to a workspace
    Mod+Shift+1...9   send the window in focus there
    Mod+Shift+E       quit Hyprbyte (closes every window)
  A click on a window focuses it. hyprctl controls Hyprbyte from a window.

  Settings: /etc/hyprbyte.conf, then ~/.config/hyprbyte.conf (see there).

  Layers: a program such as quickshell can put panels at the top or bottom
  of the screen (package.loaded["hyprbyte.state"].addLayer, see man
  hyprbyte); the built-in bar makes way for a panel at the top.
]]--
local surface = require("surface")
local tty = require("tty")
local T = term.theme
local args = arg or {}

if k.process.tty() then
  term.write("hyprbyte: already in a window; Hyprbyte runs on the screen itself\n")
  return 1
end
if package.loaded["hyprbyte.state"] then
  term.write("hyprbyte: already running\n")
  return 1
end

local screen = term.console.gpu
local SW, SH = screen.getResolution()

-- ---- settings ------------------------------------------------------------------
local conf = {
  gaps_in = SW >= 120 and 1 or 0, gaps_out = SW >= 120 and 1 or 0,
  animations = true, bar = true, mod = "alt", rounding = true, exec_once = {}, open = {},
}
local function readConf(path)
  for line in (fs.readAll(path) or ""):gmatch("[^\r\n]+") do
    local key, value = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
    if key then
      key = key:gsub("%-", "_")
      if key == "exec_once" or key == "open" then conf[key][#conf[key] + 1] = value
      elseif value == "yes" or value == "true" then conf[key] = true
      elseif value == "no" or value == "false" then conf[key] = false
      else conf[key] = tonumber(value) or value end
    end
  end
end
readConf("/etc/hyprbyte.conf")
readConf((_G.HOME or "/") .. "/.config/hyprbyte.conf")
for _, a in ipairs(args) do if a == "--no-animations" then conf.animations = false end end

local MODS = { alt = { [56] = true, [184] = true }, super = { [219] = true, [220] = true },
               ctrl = { [29] = true, [157] = true } }
local MOD = MODS[tostring(conf.mod):lower()] or MODS.alt

-- ---- state (hyprctl reads it) ---------------------------------------------------------
local state = { workspaces = {}, active = 1, queue = {}, history = {}, version = "1.1.0", conf = conf, layers = {} }
for i = 1, 9 do state.workspaces[i] = { list = {}, focus = 1, fullscreen = false } end
package.loaded["hyprbyte.state"] = state
local nextId, running = 1, true
local held, swallowed, pending = {}, {}, {}

local function ws() return state.workspaces[state.active] end

-- ---- layers: panels other programs put along the edges ------------------------------
-- layer = { namespace, anchor = "top" | "bottom", height = rows,
--           draw = function(gpu, x, y, w, h), click = function(x, y, button) }
-- Hyprbyte keeps the rows free and calls draw whenever the bar is drawn.
local function hasTopLayer()
  for _, l in ipairs(state.layers) do if l.anchor ~= "bottom" then return true end end
  return false
end
local function builtinBar() return conf.bar and not hasTopLayer() end
-- the space for windows: x, y, w, h
local function area()
  local top, bottom = builtinBar() and 1 or 0, 0
  for _, l in ipairs(state.layers) do
    if l.anchor == "bottom" then bottom = bottom + l.height else top = top + l.height end
  end
  return 1, 1 + top, SW, math.max(3, SH - top - bottom)
end
function state.addLayer(l)
  l.height = math.max(1, math.floor(tonumber(l.height) or 1))
  l.pid = l.pid or k.process.current() -- gone with its program
  state.layers[#state.layers + 1] = l
  state.relayout = true
  return l
end
function state.removeLayer(l)
  for i = #state.layers, 1, -1 do if state.layers[i] == l then table.remove(state.layers, i) end end
  state.relayout = true
end
local function focused()
  local w = ws()
  return w.list[w.focus]
end

-- ---- drawing ------------------------------------------------------------------------
local function paint(x, y, text, fg, bg)
  screen.setForeground(fg); screen.setBackground(bg or T.bg)
  screen.set(x, y, text)
end

local CORNERS = conf.rounding and { "╭", "╮", "╰", "╯" } or { "┌", "┐", "└", "┘" }
local function border(win, active)
  local r = win.rect
  if not r then return end
  local x, y, w, h = r[1], r[2], r[3], r[4]
  local c = active and T.accent or T.dim
  paint(x, y, CORNERS[1] .. string.rep("─", w - 2) .. CORNERS[2], c)
  for i = 1, h - 2 do paint(x, y + i, "│", c); paint(x + w - 1, y + i, "│", c) end
  paint(x, y + h - 1, CORNERS[3] .. string.rep("─", w - 2) .. CORNERS[4], c)
  local name = (win.term and win.term.title) or win.title
  local title = " " .. name .. " "
  if w > 6 and name ~= "" then paint(x + 2, y, term.usub(title, 1, w - 4), active and T.bright or T.muted) end
end

local function drawLayers()
  for i = #state.layers, 1, -1 do
    local l = state.layers[i]
    local p = l.pid and k.process.info(l.pid)
    if l.pid and not (p and p.state == "running") then table.remove(state.layers, i); state.relayout = true end
  end
  local top, bottom = builtinBar() and 1 or 0, 0
  for _, l in ipairs(state.layers) do
    local y
    if l.anchor == "bottom" then bottom = bottom + l.height; y = SH - bottom + 1
    else y = top + 1; top = top + l.height end
    l.rect = { 1, y, SW, l.height }
    screen.setBackground(T.base); screen.fill(1, y, SW, l.height, " ")
    local ok, err = pcall(l.draw, screen, 1, y, SW, l.height)
    if not ok then paint(1, y, term.pad((l.namespace or "layer") .. ": " .. tostring(err), SW), T.bright, T.red) end
  end
  screen.setBackground(T.bg)
end

local function bar()
  drawLayers()
  if not builtinBar() then return end
  screen.setBackground(T.base); screen.fill(1, 1, SW, 1, " ")
  local last = 5
  for i = 1, 9 do if #state.workspaces[i].list > 0 then last = math.max(last, i) end end
  local x = 1
  for i = 1, last do
    local label = " " .. i .. " "
    if i == state.active then paint(x, 1, label, T.bright, T.accent)
    elseif #state.workspaces[i].list > 0 then paint(x, 1, label, T.fg, T.base)
    else paint(x, 1, label, T.dim, T.base) end
    x = x + 3
  end
  local okC, clock = pcall(require, "clock")
  local right = ("mem %d%%"):format(math.floor(100 * (1 - computer.freeMemory() / computer.totalMemory()) + 0.5))
  if computer.maxEnergy and computer.maxEnergy() > 0 then
    right = right .. ("  ⚡%d%%"):format(math.floor(100 * computer.energy() / computer.maxEnergy() + 0.5))
  end
  if okC then right = right .. "  " .. clock.date("%H:%M") end
  right = right .. " "
  paint(SW - term.ulen(right) + 1, 1, right, T.muted, T.base)
  local win = focused()
  if win then
    local room = SW - term.ulen(right) - x - 2
    if room > 4 then
      local t = term.usub(win.term.title or win.title, 1, room)
      paint(math.max(x + 1, (SW - term.ulen(t)) // 2), 1, t, T.fg, T.base)
    end
  end
  screen.setBackground(T.bg)
end

-- dwindle: the first window takes half of the space, the rest share the
-- other half the same way; side by side when the space is wide
local function tile(list, from, x, y, w, h, out)
  local n = #list - from + 1
  if n <= 0 then return end
  if n == 1 then out[list[from]] = { x, y, w, h }; return end
  local gap = conf.gaps_in
  if w >= h * 2 then
    local w1 = (w - gap) // 2
    out[list[from]] = { x, y, w1, h }
    tile(list, from + 1, x + w1 + gap, y, w - w1 - gap, h, out)
  else
    local h1 = (h - gap) // 2
    out[list[from]] = { x, y, w, h1 }
    tile(list, from + 1, x, y + h1 + gap, w, h - h1 - gap, out)
  end
end

local function layout()
  state.relayout = false
  local g = conf.gaps_out
  local x0, y0, w0, h0 = area()
  local ax, ay, aw, ah = x0 + g, y0 + g, w0 - 2 * g, h0 - 2 * g
  local rects = {}
  local cur = ws()
  if cur.fullscreen and focused() then rects[focused()] = { x0, y0, w0, h0 }
  else tile(cur.list, 1, ax, ay, aw, ah, rects) end
  -- hide everything first, then place and show this workspace's windows
  for _, space in ipairs(state.workspaces) do
    for _, win in ipairs(space.list) do win.surface.show(false); win.rect = nil end
  end
  screen.setBackground(T.bg); screen.setForeground(T.fg)
  screen.fill(1, 1, SW, SH, " ")
  for win, r in pairs(rects) do
    if r[3] >= 4 and r[4] >= 3 then
      win.rect = r
      local iw, ih = r[3] - 2, r[4] - 2
      local _, cy = win.term.getCursor()
      local drop = math.max(0, cy - ih)
      win.surface.place(r[1] + 1, r[2] + 1, iw, ih, drop)
      win.term.resize(drop)
      win.surface.show(true)
    end
  end
  for _, win in ipairs(cur.list) do border(win, win == focused()) end
  bar()
end

-- wait a moment for an animation, keeping the signals that arrive meanwhile
local function pause(seconds)
  local deadline = computer.uptime() + seconds
  while computer.uptime() < deadline do
    local sig = table.pack(k.event.pull(deadline - computer.uptime()))
    if sig[1] then pending[#pending + 1] = sig end
  end
end

-- a window opening: its frame grows from the middle (like Hyprland's popin)
local function popin(r)
  if not conf.animations or not r then return end
  local cx, cy = r[1] + r[3] // 2, r[2] + r[4] // 2
  for _, f in ipairs({ 0.3, 0.6 }) do
    local w, h = math.max(2, math.floor(r[3] * f)), math.max(2, math.floor(r[4] * f))
    border({ rect = { cx - w // 2, cy - h // 2, w, h }, title = "" }, true)
    pause(0.04)
  end
end

-- ---- windows -----------------------------------------------------------------------
local function open(cmd)
  local s = surface.new(screen, 1, 2, 10, 3)
  local t = tty.new(s)
  local win = { id = nextId, title = cmd or "byteshell", surface = s, term = t, ws = state.active }
  nextId = nextId + 1
  local pid, err = k.process.spawn(function()
    if cmd then return shell.execute(cmd) end
    shell.loop()
  end, { name = "hyprbyte: " .. win.title, tty = t, onexit = function() win.closed = true end })
  if not pid then return nil, err end
  win.pid = pid
  local cur = ws()
  table.insert(cur.list, math.min(#cur.list + 1, cur.focus + 1), win)
  cur.focus = math.min(#cur.list, cur.focus + (#cur.list > 1 and 1 or 0))
  cur.fullscreen = false
  local rects = {}
  local x0, y0, w0, h0 = area()
  local g = conf.gaps_out
  tile(cur.list, 1, x0 + g, y0 + g, w0 - 2 * g, h0 - 2 * g, rects)
  popin(rects[win])
  layout()
  return win
end

local function close(win)
  if win then k.tty.hangup(win.term) end
end

-- exec-once: a program in the background (a panel, a daemon), no window;
-- what it prints goes to the system log
local daemons = {}
local function exec(cmd)
  local pid = k.process.spawn(function()
    local log = setmetatable({}, { __newindex = function(_, _, text)
      for line in tostring(text):gmatch("[^\n]+") do k.log(line, "hyprbyte") end
    end })
    shell.setErrorSink(function(text) log[1] = text end)
    return shell.withIO({ output = log }, shell.execute, cmd)
  end, { name = cmd })
  daemons[#daemons + 1] = pid
end

-- forget windows whose programs ended
local function sweep()
  local changed = false
  for _, space in ipairs(state.workspaces) do
    for i = #space.list, 1, -1 do
      if space.list[i].closed then
        space.list[i].surface.show(false)
        table.remove(space.list, i)
        if space.focus > i or space.focus > #space.list then space.focus = math.max(1, space.focus - 1) end
        changed = true
      end
    end
  end
  if changed then layout() end
end

local function focus(delta)
  local cur = ws()
  if #cur.list < 2 then return end
  cur.focus = (cur.focus - 1 + delta) % #cur.list + 1
  if cur.fullscreen then layout()
  else
    for _, win in ipairs(cur.list) do border(win, win == focused()) end
    bar()
  end
end

local function swap(delta)
  local cur = ws()
  local j = cur.focus + delta
  if j < 1 or j > #cur.list then return end
  cur.list[cur.focus], cur.list[j] = cur.list[j], cur.list[cur.focus]
  cur.focus = j
  layout()
end

local function workspace(n)
  if n == state.active or not state.workspaces[n] then return end
  state.active = n
  layout()
end

local function moveTo(n)
  local win, cur = focused(), ws()
  if not win or n == state.active or not state.workspaces[n] then return end
  table.remove(cur.list, cur.focus)
  cur.focus = math.max(1, math.min(cur.focus, #cur.list))
  local dest = state.workspaces[n]
  dest.list[#dest.list + 1] = win
  dest.focus = #dest.list
  win.ws = n
  layout()
end

-- Mod+D: a box in the middle that asks for a command line
local function launcher()
  local w = math.min(SW - 4, 50)
  local x, y = (SW - w) // 2 + 1, SH // 3
  border({ rect = { x, y, w, 3 }, title = "run" }, true)
  screen.setBackground(T.bg); screen.fill(x + 1, y + 1, w - 2, 1, " ")
  term.setCursor(x + 2, y + 1)
  term.setForeground(T.bright)
  local line = term.read({ history = state.history }) or ""
  term.setForeground(T.fg)
  line = line:gsub("^%s+", ""):gsub("%s+$", "")
  held, swallowed = {}, {} -- the keys let go of while typing went to the box
  layout()
  if line ~= "" then open(line) end
end

-- ---- hyprctl dispatch ---------------------------------------------------------------
local DISPATCH = {
  exec = function(a) if a ~= "" then open(a) end end,
  killactive = function() close(focused()) end,
  workspace = function(a) workspace(tonumber(a) or state.active) end,
  movetoworkspace = function(a) moveTo(tonumber(a) or state.active) end,
  fullscreen = function() ws().fullscreen = not ws().fullscreen; layout() end,
  cyclenext = function() focus(1) end,
  exit = function() running = false end,
}
state.dispatchers = DISPATCH
state.focused = focused

-- ---- keys ---------------------------------------------------------------------------
local BIND = {
  [28] = function() open() end,                -- Enter
  [32] = launcher,                             -- D
  [16] = function() close(focused()) end,      -- Q
  [33] = DISPATCH.fullscreen,                  -- F
  [15] = function() focus(1) end,              -- Tab
  [203] = function() focus(-1) end, [200] = function() focus(-1) end,
  [205] = function() focus(1) end, [208] = function() focus(1) end,
}
local SHIFT_BIND = {
  [18] = DISPATCH.exit,                        -- Shift+E
  [203] = function() swap(-1) end, [200] = function() swap(-1) end,
  [205] = function() swap(1) end, [208] = function() swap(1) end,
}
for i = 1, 9 do
  BIND[i + 1] = function() workspace(i) end    -- keys 1..9 are codes 2..10
  SHIFT_BIND[i + 1] = function() moveTo(i) end
end

local function modHeld() for c in pairs(MOD) do if held[c] then return true end end return false end
local function shiftHeld() return held[42] or held[54] end

local function handle(sig)
  local ev, code = sig[1], sig[4]
  if ev == "key_down" or ev == "key_up" then
    held[code] = ev == "key_down" or nil
    if MOD[code] then return end
    if ev == "key_down" and modHeld() then
      local fn = (shiftHeld() and SHIFT_BIND[code]) or (not shiftHeld() and BIND[code])
      if fn then swallowed[code] = true; fn(); return end
    end
    if ev == "key_up" and swallowed[code] then swallowed[code] = nil; return end
    if focused() then k.tty.input(focused().term, table.unpack(sig, 1, sig.n)) end
  elseif ev == "clipboard" then
    if focused() then k.tty.input(focused().term, table.unpack(sig, 1, sig.n)) end
  elseif ev == "touch" then
    local x, y = sig[3], sig[4]
    for _, l in ipairs(state.layers) do
      local r = l.rect
      if r and l.click and y >= r[2] and y < r[2] + r[4] then
        local ok, e = pcall(l.click, x - r[1] + 1, y - r[2] + 1, sig[5])
        if not ok then k.log("layer " .. tostring(l.namespace) .. ": " .. tostring(e), "hyprbyte") end
        return
      end
    end
    for i, win in ipairs(ws().list) do
      local r = win.rect
      if r and x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] then
        if i ~= ws().focus then ws().focus = i; focus(0) end
      end
    end
  end
end

-- ---- main loop -------------------------------------------------------------------------
local savedInterrupt = k.event.interruptible
k.event.interruptible = 0 -- Ctrl+C belongs to the windows
local okRun, err = pcall(function()
  term.clear()
  layout()
  for _, cmd in ipairs(conf.exec_once) do exec(cmd) end
  for _, cmd in ipairs(conf.open) do open(cmd) end
  if #ws().list == 0 then open() end
  local nextBar = computer.uptime() + 1
  while running do
    local sig = table.remove(pending, 1)
    if not sig then sig = table.pack(k.event.pull(0.25)) end
    if sig[1] then handle(sig) end
    while #state.queue > 0 do
      local q = table.remove(state.queue, 1)
      if DISPATCH[q[1]] then DISPATCH[q[1]](q[2] or "") end
    end
    sweep()
    if state.relayout then layout() end
    -- a window's title follows what runs in it (its shell sets term.title)
    local changed = false
    for _, win in ipairs(ws().list) do
      local title = win.term.title or win.title
      if title ~= win.shown then win.shown = title; changed = true end
    end
    if changed then
      for _, win in ipairs(ws().list) do border(win, win == focused()) end
      bar()
    end
    if computer.uptime() >= nextBar then bar(); nextBar = computer.uptime() + 1 end
  end
end)
k.event.interruptible = savedInterrupt
for _, space in ipairs(state.workspaces) do
  for _, win in ipairs(space.list) do close(win) end
end
for _, pid in ipairs(daemons) do k.process.kill(pid) end
package.loaded["hyprbyte.state"] = nil
screen.setBackground(T.bg); screen.setForeground(T.fg)
term.clear()
if not okRun then error(err, 0) end
return 0
