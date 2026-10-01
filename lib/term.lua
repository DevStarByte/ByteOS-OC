--[[
  /lib/term.lua - terminal driver for ByteOS
  Wraps GPU + screen + keyboard into print/read/clear primitives.

  * UTF-8 aware output (box drawing, block glyphs, ✓ ...), written in runs
    instead of one GPU call per byte.
  * Blinking block cursor while waiting for input.
  * Line editor for term.read(): cursor movement, history, paste, ^C / ^D.
  * The shared colour theme (lib/theme.lua) is loaded into the GPU palette.
]]--

local component = component
local computer  = computer
local k         = _G.kernel
local theme     = require("theme")

local term = {}
term.theme = theme

local gpu      = component.proxy(component.list("gpu")())
local screen   = component.list("screen")()
if gpu and screen then
  gpu.bind(screen)
  if gpu.maxDepth then
    local maxDepth = gpu.maxDepth()
    if gpu.getDepth() < maxDepth then gpu.setDepth(maxDepth) end
  end
end

term.gpu = gpu
local W, H = gpu.getResolution()
term.width, term.height = W, H
term.depth = gpu.getDepth and gpu.getDepth() or 1

local cx, cy = 1, 1

-- ---- UTF-8 helpers ----------------------------------------------------------
-- Lua's # and :sub() count bytes; screen layout needs characters. OC exposes
-- a native `unicode` library; fall back to the utf8 module when testing.
local ulen = (unicode and unicode.len) or function(s) return utf8.len(s) or #s end
local usub = (unicode and unicode.sub) or function(s, i, j)
  local n = utf8.len(s) or #s
  j = j or n
  if i < 0 then i = math.max(1, n + i + 1) end
  if j < 0 then j = n + j + 1 end
  if i > j or i > n then return "" end
  local bi = utf8.offset(s, i)
  local bj = utf8.offset(s, math.min(j, n) + 1)
  return s:sub(bi, (bj or #s + 1) - 1)
end
term.ulen, term.usub = ulen, usub

-- Pad (or truncate) s to exactly n display columns.
function term.pad(s, n)
  local l = ulen(s)
  if l > n then return usub(s, 1, n) end
  return s .. string.rep(" ", n - l)
end

-- ---- Palette ---------------------------------------------------------------
-- Program the GPU's editable palette with the given 24-bit colors, so that
-- plain setForeground/setBackground(hex) calls land exactly on them instead
-- of being auto-snapped to the nearest default entry.
--   Tier 2 (depth 4): the 16 palette slots are the *only* colours available.
--   Tier 3 (depth 8): 240 fixed colours + 16 editable slots; hex values snap
--                     to the closest of all 256, so our slots win for themed
--                     colours.
--   Tier 1 (depth 1): monochrome, no palette.
function term.setPalette(colors)
  if not gpu.setPaletteColor or gpu.getDepth() < 4 then return end
  local seen, slot = {}, 0
  for _, color in ipairs(colors) do
    if not seen[color] and slot < 16 then
      seen[color] = true
      gpu.setPaletteColor(slot, color)
      slot = slot + 1
    end
  end
end

if term.depth >= 4 then term.setPalette(theme.palette)
else theme.monochrome() end

-- ---- Basic state -----------------------------------------------------------
local function scrollIfNeeded()
  if cy > H then
    local fg = gpu.setForeground(theme.fg)
    local bg = gpu.setBackground(theme.bg)
    gpu.copy(1, 2, W, H - 1, 0, -1)
    gpu.fill(1, H, W, 1, " ")
    gpu.setForeground(fg); gpu.setBackground(bg)
    cy = H
  end
end

function term.clear()
  gpu.setBackground(theme.bg)
  gpu.setForeground(theme.fg)
  gpu.fill(1, 1, W, H, " ")
  cx, cy = 1, 1
end

-- Clear the rest of the current line (from the cursor).
function term.clearLine()
  if cx <= W then gpu.fill(cx, cy, W - cx + 1, 1, " ") end
end

function term.setCursor(x, y) cx, cy = x, y end
function term.getCursor() return cx, cy end
function term.size() return W, H end
function term.setForeground(c) return gpu.setForeground(c) end
function term.setBackground(c) return gpu.setBackground(c) end

-- ---- Output ----------------------------------------------------------------
local function newline()
  cx, cy = 1, cy + 1
  scrollIfNeeded()
end

-- Write a run of printable text, wrapping at the right edge. The wrap is
-- deferred until the next character so a line that exactly fills the screen
-- followed by "\n" does not produce an extra blank line.
local function writeRun(run)
  while run ~= "" do
    if cx > W then newline() end
    local room  = W - cx + 1
    local chunk = usub(run, 1, room)
    gpu.set(cx, cy, chunk)
    local n = ulen(chunk)
    cx = cx + n
    run = usub(run, n + 1)
  end
end

function term.write(s)
  s = tostring(s)
  local i, len = 1, #s
  while i <= len do
    local j = s:find("[\n\r\t]", i)
    if not j then writeRun(s:sub(i)); break end
    if j > i then writeRun(s:sub(i, j - 1)) end
    local c = s:sub(j, j)
    if c == "\n" then
      newline()
    elseif c == "\r" then
      cx = 1
    else -- tab: advance to the next multiple of 4
      if cx > W then newline() end
      local advance = 4 - ((cx - 1) % 4)
      advance = math.min(advance, W - cx + 1)
      gpu.set(cx, cy, string.rep(" ", advance))
      cx = cx + advance
    end
    i = j + 1
  end
end

-- Write text in a colour, then restore the previous foreground.
function term.cwrite(color, s)
  local old = gpu.setForeground(color)
  term.write(s)
  gpu.setForeground(old)
end

function term.print(...)
  local n = select("#", ...)
  local args = { ... }
  for i = 1, n do
    if i > 1 then term.write("\t") end
    term.write(tostring(args[i]))
  end
  term.write("\n")
end
_G.print = term.print

-- ---- Cursor ----------------------------------------------------------------
-- A block cursor drawn by inverting the cell under it.
local cursor = { shown = false }

local function cursorDraw(on)
  if on == cursor.shown then return end
  if on then
    local x, y = math.min(cx, W), cy
    local ok, ch, fg, bg = pcall(gpu.get, x, y)
    if not ok then return end
    cursor.x, cursor.y, cursor.ch, cursor.fg, cursor.bg = x, y, ch, fg, bg
    local ofg = gpu.setForeground(bg == fg and theme.bg or bg)
    local obg = gpu.setBackground(fg == bg and theme.fg or fg)
    gpu.set(x, y, ch)
    gpu.setForeground(ofg); gpu.setBackground(obg)
  else
    local ofg = gpu.setForeground(cursor.fg)
    local obg = gpu.setBackground(cursor.bg)
    gpu.set(cursor.x, cursor.y, cursor.ch)
    gpu.setForeground(ofg); gpu.setBackground(obg)
  end
  cursor.shown = on
end

-- ---- Keyboard --------------------------------------------------------------
local CODE = {
  [28] = "enter", [156] = "enter", [14] = "backspace", [15] = "tab", [1] = "escape",
  [200] = "up", [208] = "down", [203] = "left", [205] = "right",
  [199] = "home", [207] = "end", [201] = "pageup", [209] = "pagedown",
  [211] = "delete", [210] = "insert",
}
-- scan code -> letter, used to report Ctrl+<letter> combos
local LETTER = {}
do
  local rows = { { 16, "qwertyuiop" }, { 30, "asdfghjkl" }, { 44, "zxcvbnm" } }
  for _, r in ipairs(rows) do
    for i = 1, #r[2] do LETTER[r[1] + i - 1] = r[2]:sub(i, i) end
  end
end
local ctrlDown = false

-- Read a single key. Returns:
--   ch (string) for printable input (any unicode character),
--   "enter", "backspace", "tab", "escape", "delete", "insert",
--   "up","down","left","right","home","end","pageup","pagedown",
--   "ctrl+<letter>" (e.g. "ctrl+s"), "interrupt",
--   or "paste", <text> when the player pastes from the clipboard.
-- With showCursor, a blinking cursor is drawn at the terminal cursor position.
function term.readKey(showCursor)
  local blinkAt = computer.uptime()
  while true do
    if showCursor then
      local now = computer.uptime()
      if now >= blinkAt then
        cursorDraw(not cursor.shown)
        blinkAt = now + 0.5
      end
    end
    local ev, _, ch, code = k.event.pull(showCursor and math.max(0.05, blinkAt - computer.uptime()) or nil)
    local result, extra
    if ev == "interrupted" then
      result = "interrupt"
    elseif ev == "clipboard" then
      result, extra = "paste", ch
    elseif ev == "key_up" then
      if code == 29 or code == 157 then ctrlDown = false end
    elseif ev == "key_down" then
      if code == 29 or code == 157 then
        ctrlDown = true
      elseif ctrlDown and LETTER[code] then
        result = "ctrl+" .. LETTER[code]
      elseif CODE[code] then
        result = CODE[code]
      elseif ch and ch >= 32 and ch ~= 127 then
        result = (unicode and unicode.char or utf8.char)(math.floor(ch))
      end
    end
    if result then
      cursorDraw(false)
      return result, extra
    end
  end
end

-- ---- Line editor -----------------------------------------------------------
-- term.read([opts]) -> string, or nil on ^D at an empty line.
--   opts.mask     : character to echo instead of the input (passwords)
--   opts.history  : table of previous lines; Up/Down walks it, new lines
--                   are appended to it
--   opts.default  : initial buffer contents
-- Long input scrolls horizontally inside the space left on the line.
function term.read(opts)
  opts = opts or {}
  local history = opts.history
  local buf = opts.default or ""
  local pos = ulen(buf)            -- characters before the cursor
  local off = 0                    -- horizontal scroll offset
  local startX, startY = math.min(cx, W), cy
  local room = math.max(1, W - startX)   -- keep one column for the cursor
  local hidx = history and #history + 1
  local stash

  local function shown()
    if opts.mask then return string.rep(opts.mask, ulen(buf)) end
    return buf
  end

  local function redraw()
    if pos < off then off = pos end
    if pos > off + room then off = pos - room end
    local view = usub(shown(), off + 1, off + room)
    gpu.fill(startX, startY, W - startX + 1, 1, " ")
    if view ~= "" then gpu.set(startX, startY, view) end
    cx, cy = startX + pos - off, startY
  end

  local function insert(s)
    buf = usub(buf, 1, pos) .. s .. usub(buf, pos + 1)
    pos = pos + ulen(s)
  end

  redraw()
  while true do
    local key, extra = term.readKey(true)
    if key == "enter" then
      cx = startX + ulen(shown()) - off
      if cx > W then cx = W end
      term.write("\n")
      if history and buf ~= "" and history[#history] ~= buf and not opts.mask then
        history[#history + 1] = buf
      end
      return buf
    elseif key == "ctrl+c" or key == "interrupt" then
      cx = math.min(W, startX + ulen(shown()) - off)
      term.cwrite(theme.muted, "^C")
      term.write("\n")
      return ""
    elseif key == "ctrl+d" then
      if buf == "" then term.write("\n"); return nil end
    elseif key == "backspace" then
      if pos > 0 then buf = usub(buf, 1, pos - 1) .. usub(buf, pos + 1); pos = pos - 1 end
    elseif key == "delete" then
      buf = usub(buf, 1, pos) .. usub(buf, pos + 2)
    elseif key == "left" then pos = math.max(0, pos - 1)
    elseif key == "right" then pos = math.min(ulen(buf), pos + 1)
    elseif key == "home" or key == "ctrl+a" then pos = 0
    elseif key == "end" or key == "ctrl+e" then pos = ulen(buf)
    elseif key == "ctrl+u" then buf = usub(buf, pos + 1); pos = 0
    elseif key == "ctrl+w" then
      local before = usub(buf, 1, pos):gsub("%s*[^%s]*$", "")
      buf = before .. usub(buf, pos + 1); pos = ulen(before)
    elseif key == "up" and history and hidx > 1 then
      if hidx == #history + 1 then stash = buf end
      hidx = hidx - 1; buf = history[hidx]; pos = ulen(buf)
    elseif key == "down" and history and hidx <= #history then
      hidx = hidx + 1
      buf = (hidx == #history + 1) and (stash or "") or history[hidx]
      pos = ulen(buf)
    elseif key == "paste" then
      insert(((extra or ""):match("^[^\r\n]*")))
    elseif ulen(key) == 1 then
      insert(key)
    end
    redraw()
  end
end
_G.read = term.read

return term
