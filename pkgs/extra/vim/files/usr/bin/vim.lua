--[[
  vim [file] - a modal text editor in the style of Vim

  Normal mode (Esc gets you there):
    h j k l, arrows   move           w b      next / previous word
    0 ^ $             line start, first character, end
    gg G  5G          first, last line, line 5
    ^F ^B ^D ^U       page / half page down and up
    i a I A o O       insert: before, after, line start, line end,
                      new line below, above
    x X  r<c>  ~      delete a character, the one before, replace, swap case
    dd dw D  yy  p P  delete line, word, to the end; copy line; put after,
                      before (a count works: 3dd, 2yy, 5x)
    J  u  ^R          join lines, undo, redo
    /text  n N        search forward, next, previous
    ZZ ZQ             save and quit, quit without saving
  Command mode (:):
    :w [file]  :q  :q!  :wq  :x  :e!  :42  :set nu / nonu
    :s/old/new/[g]   :%s/old/new/g   (plain text, not patterns)
]]--
local T = term.theme
local gpu = term.gpu
local ulen, usub = term.ulen, term.usub
local W, H = term.size()
local VIEW = H - 1 -- the last row is the command line

local args = arg or {}
local name = args[1]
local path = name and shell.normalize(name)
if path and fs.isDirectory(path) then term.write("vim: " .. name .. " is a directory\n"); return 1 end

local lines = {}
local function load()
  lines = {}
  if path and fs.exists(path) then
    local data = (fs.readAll(path) or ""):gsub("\r\n", "\n")
    for ln in (data .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = ln end
    if #lines > 1 and lines[#lines] == "" then lines[#lines] = nil end
  end
  if #lines == 0 then lines[1] = "" end
end
load()

local row, col, top, left = 1, 0, 1, 0
local mode, numbers, modified = "normal", false, false
local message, messageColor
local undo, redo, register = {}, {}, nil
local lastSearch

local function bytes()
  local n = 0
  for _, l in ipairs(lines) do n = n + #l + 1 end
  return n
end
if not path then message = "VIM - Vi IMproved, ByteOS edition   :q to quit"
elseif fs.exists(path) then message = ('"%s" %dL, %dB'):format(name, #lines, bytes())
else message = ('"%s" [New]'):format(name) end

-- ---- undo -------------------------------------------------------------------------
local function snapshot()
  local copy = {}
  for i, l in ipairs(lines) do copy[i] = l end
  return { lines = copy, row = row, col = col }
end
local function change() -- call before every edit
  undo[#undo + 1] = snapshot()
  if #undo > 100 then table.remove(undo, 1) end
  redo = {}
  modified = true
end
local function restore(from, to, what)
  local s = table.remove(from)
  if not s then message = what == "undo" and "Already at oldest change" or "Already at newest change"; return end
  to[#to + 1] = snapshot()
  lines, row, col = s.lines, s.row, s.col
  modified = true
  message = ("1 change; %s"):format(what == "undo" and "before #" .. (#undo + 1) or "after #" .. #undo)
end

-- ---- drawing --------------------------------------------------------------------------
local function gutter() return numbers and (math.max(3, #tostring(#lines)) + 1) or 0 end
local function lastCol()
  local n = ulen(lines[row])
  if mode == "insert" then return n end
  return math.max(0, n - 1)
end

local function drawLine(i)
  local y = i - top + 1
  if y < 1 or y > VIEW then return end
  gpu.setBackground(T.bg); gpu.fill(1, y, W, 1, " ")
  local line = lines[i]
  if not line then gpu.setForeground(T.blue); gpu.set(1, y, "~"); return end
  local g = gutter()
  if numbers then gpu.setForeground(T.yellow); gpu.set(1, y, ("%" .. (g - 1) .. "d"):format(i)) end
  gpu.setForeground(T.fg)
  gpu.set(g + 1, y, usub(line, left + 1, left + W - g))
end
local function drawAll() for i = top, top + VIEW - 1 do drawLine(i) end end

local function drawStatus()
  gpu.setBackground(T.bg); gpu.fill(1, H, W, 1, " ")
  if mode == "insert" then
    gpu.setForeground(T.bright); gpu.set(1, H, "-- INSERT --")
  elseif message then
    gpu.setForeground(messageColor or T.fg); gpu.set(1, H, usub(message, 1, W - 20))
  end
  local where
  if #lines <= VIEW then where = "All"
  elseif top == 1 then where = "Top"
  elseif top + VIEW - 1 >= #lines then where = "Bot"
  else where = ("%d%%"):format(math.floor(100 * (top - 1) / (#lines - VIEW))) end
  gpu.setForeground(T.fg)
  gpu.set(W - 17, H, ("%d,%d"):format(row, col + 1))
  gpu.set(W - 3, H, where)
end

local function scroll()
  local moved = false
  if row < top then top = row; moved = true end
  if row >= top + VIEW then top = row - VIEW + 1; moved = true end
  local room = W - gutter() - 1
  if col < left then left = col; moved = true end
  if col >= left + room then left = col - room + 1; moved = true end
  return moved
end

-- ---- motions ---------------------------------------------------------------------------
local function class(c)
  if c == nil or c == "" or c:match("%s") then return 0 end
  if c:match("[%w_]") then return 1 end
  return 2
end
local function charAt(r, c) return usub(lines[r], c + 1, c + 1) end

local function wordForward()
  local line, n = lines[row], ulen(lines[row])
  local c, start = col, class(charAt(row, col))
  while c < n and class(charAt(row, c)) == start and start ~= 0 do c = c + 1 end
  while c < n and class(charAt(row, c)) == 0 do c = c + 1 end
  if c >= n and row < #lines then
    row = row + 1
    local ind = lines[row]:match("^%s*")
    col = ulen(ind)
  else
    col = math.min(c, math.max(0, n - 1))
  end
  return line
end
local function wordBack()
  local c = col
  if c == 0 then
    if row > 1 then row = row - 1; col = math.max(0, ulen(lines[row]) - 1) end
    return
  end
  c = c - 1
  while c > 0 and class(charAt(row, c)) == 0 do c = c - 1 end
  local cl = class(charAt(row, c))
  while c > 0 and class(charAt(row, c - 1)) == cl do c = c - 1 end
  col = c
end
local function firstNonBlank() col = ulen(lines[row]:match("^%s*")) end

-- ---- search -----------------------------------------------------------------------------
local function find(q, backward)
  if not q or q == "" then message = "E35: No previous regular expression"; messageColor = T.red; return end
  local n = #lines
  for step = 1, n + 1 do
    local i
    if backward then i = (row - 1 - (step - 1) - 1) % n + 1 else i = (row - 1 + (step - 1)) % n + 1 end
    local line = lines[i]
    local hits, s = {}, 1
    while true do
      local a = line:find(q, s, true)
      if not a then break end
      hits[#hits + 1] = ulen(line:sub(1, a - 1)); s = a + 1
    end
    local pick
    if backward then
      for j = #hits, 1, -1 do if step > 1 or i ~= row or hits[j] < col then pick = hits[j]; break end end
    else
      for _, h in ipairs(hits) do if step > 1 or i ~= row or h > col then pick = h; break end end
    end
    if pick then
      local wrapped = (not backward and i < row) or (backward and i > row)
      row, col = i, pick
      message = "/" .. q
      if wrapped then message, messageColor = backward and "search hit TOP, continuing at BOTTOM"
        or "search hit BOTTOM, continuing at TOP", T.red end
      return
    end
  end
  message, messageColor = "E486: Pattern not found: " .. q, T.red
end

-- ---- the command line --------------------------------------------------------------------
local function readCommand(prefix)
  gpu.setBackground(T.bg); gpu.fill(1, H, W, 1, " ")
  gpu.setForeground(T.fg); gpu.set(1, H, prefix)
  term.setCursor(2, H)
  return term.read()
end

local running = true
local function write(target, force)
  target = target ~= "" and target or name
  if not target then message, messageColor = "E32: No file name", T.red; return false end
  local p = shell.normalize(target)
  local ok, err = fs.writeAll(p, table.concat(lines, "\n") .. "\n")
  if not ok then message, messageColor = ('"%s" E212: Can\'t open file for writing: %s'):format(target, tostring(err)), T.red; return false end
  if not name then name, path = target, p end
  if p == path then modified = false end
  message = ('"%s" %dL, %dB written'):format(target, #lines, bytes())
  return true
end

local function substitute(text, all)
  local sep = text:sub(1, 1)
  local parts = {}
  for piece in (text:sub(2) .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do parts[#parts + 1] = piece end
  local old, new, flags = parts[1], parts[2], parts[3] or ""
  if not old or old == "" or not new then message, messageColor = "E486: Pattern not found", T.red; return end
  local global = flags:find("g") ~= nil
  local from, to = row, row
  if all then from, to = 1, #lines end
  local count, lastRow = 0, nil
  local plainOld = old:gsub("%p", "%%%0")
  local plainNew = new:gsub("%%", "%%%%")
  for i = from, to do
    local result, n
    if global then result, n = lines[i]:gsub(plainOld, plainNew)
    else result, n = lines[i]:gsub(plainOld, plainNew, 1) end
    if n > 0 then
      if count == 0 then change() end
      lines[i] = result; count = count + n; lastRow = i
    end
  end
  if count == 0 then message, messageColor = "E486: Pattern not found: " .. old, T.red; return end
  row, col = lastRow, 0
  if count > 1 then message = ("%d substitutions on %d lines"):format(count, to - from + 1) end
end

local function command(cmd)
  cmd = (cmd or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local word, rest = cmd:match("^(%S+)%s*(.*)$")
  if not word then return end
  if tonumber(word) then
    row = math.max(1, math.min(#lines, math.floor(tonumber(word)))); firstNonBlank(); return
  end
  if word == "w" or word == "w!" then write(rest)
  elseif word == "q" then
    if modified then message, messageColor = "E37: No write since last change (add ! to override)", T.red
    else running = false end
  elseif word == "q!" or word == "qa!" or word == "qa" and not modified then running = false
  elseif word == "wq" or word == "x" or word == "wq!" or word == "x!" then
    if word:sub(1, 1) == "x" and not modified then running = false
    elseif write(rest) then running = false end
  elseif word == "e!" then
    load(); row, col = math.min(row, #lines), 0; modified = false; undo, redo = {}, {}
    message = ('"%s" %dL, %dB'):format(name or "", #lines, bytes())
  elseif word == "set" then
    if rest == "nu" or rest == "number" then numbers = true
    elseif rest == "nonu" or rest == "nonumber" then numbers = false
    else message, messageColor = "E518: Unknown option: " .. rest, T.red end
  elseif word == "noh" or word == "nohlsearch" then -- nothing is highlighted anyway
  elseif cmd:match("^%%s%p") then substitute(cmd:sub(3), true)
  elseif cmd:match("^s%p") then substitute(cmd:sub(2), false)
  else message, messageColor = "E492: Not an editor command: " .. cmd, T.red end
end

-- ---- normal mode ---------------------------------------------------------------------------
local function insertAt(text)
  local line = lines[row]
  lines[row] = usub(line, 1, col) .. text .. usub(line, col + 1)
  col = col + ulen(text)
end

local pending, count = nil, ""

local function deleteLines(n)
  n = math.min(n, #lines - row + 1)
  local taken = {}
  for _ = 1, n do taken[#taken + 1] = table.remove(lines, row) end
  if #lines == 0 then lines[1] = "" end
  row = math.min(row, #lines)
  firstNonBlank()
  return taken
end

local function normal(key, extra)
  local n = tonumber(count) or 1
  -- an operator or prefix waiting for its second key
  if pending then
    local op = pending
    pending = nil
    if op == "d" and key == "d" then
      change(); register = { lines = deleteLines(n), linewise = true }
      if n > 2 then message = ("%d fewer lines"):format(n) end
    elseif op == "d" and key == "w" then
      change()
      local line = lines[row]
      local start, r0 = col, row
      for _ = 1, n do wordForward() end
      if row ~= r0 then row, col = r0, ulen(line) end
      register = { text = usub(line, start + 1, col), linewise = false }
      lines[row] = usub(line, 1, start) .. usub(line, col + 1)
      col = start
    elseif op == "d" and (key == "$" or key == "end") then
      change(); register = { text = usub(lines[row], col + 1) }; lines[row] = usub(lines[row], 1, col)
    elseif op == "y" and key == "y" then
      local taken = {}
      for i = row, math.min(#lines, row + n - 1) do taken[#taken + 1] = lines[i] end
      register = { lines = taken, linewise = true }
      if #taken > 2 then message = ("%d lines yanked"):format(#taken) end
    elseif op == "g" and key == "g" then
      row = (count ~= "") and math.max(1, math.min(#lines, n)) or 1; firstNonBlank()
    elseif op == "r" and ulen(key) == 1 then
      change(); lines[row] = usub(lines[row], 1, col) .. key .. usub(lines[row], col + 2)
    elseif op == "Z" and key == "Z" then command("x")
    elseif op == "Z" and key == "Q" then running = false
    end
    count = ""
    return
  end

  if key:match("^%d$") and (key ~= "0" or count ~= "") then count = count .. key; return end

  if key == "h" or key == "left" or key == "backspace" then col = math.max(0, col - n)
  elseif key == "l" or key == "right" or key == " " then col = col + n
  elseif key == "j" or key == "down" or key == "enter" then row = math.min(#lines, row + n)
  elseif key == "k" or key == "up" then row = math.max(1, row - n)
  elseif key == "0" or key == "home" then col = 0
  elseif key == "$" or key == "end" then col = ulen(lines[row])
  elseif key == "^" then firstNonBlank()
  elseif key == "w" then for _ = 1, n do wordForward() end
  elseif key == "b" then for _ = 1, n do wordBack() end
  elseif key == "G" then row = (count ~= "") and math.max(1, math.min(#lines, n)) or #lines; firstNonBlank()
  elseif key == "ctrl+f" or key == "pagedown" then row = math.min(#lines, row + VIEW - 2); top = math.min(top + VIEW - 2, math.max(1, #lines - VIEW + 1))
  elseif key == "ctrl+b" or key == "pageup" then row = math.max(1, row - VIEW + 2); top = math.max(1, top - VIEW + 2)
  elseif key == "ctrl+d" then row = math.min(#lines, row + VIEW // 2)
  elseif key == "ctrl+u" then row = math.max(1, row - VIEW // 2)
  elseif key == "i" then change(); mode = "insert"
  elseif key == "a" then change(); mode = "insert"; col = math.min(col + 1, ulen(lines[row]))
  elseif key == "I" then change(); mode = "insert"; firstNonBlank()
  elseif key == "A" then change(); mode = "insert"; col = ulen(lines[row])
  elseif key == "o" then change(); table.insert(lines, row + 1, ""); row, col, mode = row + 1, 0, "insert"
  elseif key == "O" then change(); table.insert(lines, row, ""); col, mode = 0, "insert"
  elseif key == "x" or key == "delete" then
    if ulen(lines[row]) > 0 then
      change()
      register = { text = usub(lines[row], col + 1, col + n) }
      lines[row] = usub(lines[row], 1, col) .. usub(lines[row], col + n + 1)
    end
  elseif key == "X" then
    if col > 0 then
      change()
      local from = math.max(0, col - n)
      register = { text = usub(lines[row], from + 1, col) }
      lines[row] = usub(lines[row], 1, from) .. usub(lines[row], col + 1)
      col = from
    end
  elseif key == "D" then pending = "d"; normal("$"); return
  elseif key == "~" then
    local c = charAt(row, col)
    if c ~= "" then
      change()
      lines[row] = usub(lines[row], 1, col) .. (c:lower() == c and c:upper() or c:lower()) .. usub(lines[row], col + 2)
      col = col + 1
    end
  elseif key == "J" then
    if row < #lines then
      change()
      local nextLine = lines[row + 1]:gsub("^%s+", "")
      col = ulen(lines[row])
      lines[row] = lines[row]:gsub("%s+$", "") .. (nextLine ~= "" and " " or "") .. nextLine
      table.remove(lines, row + 1)
    end
  elseif key == "p" or key == "P" then
    if register then
      change()
      for _ = 1, n do
        if register.linewise then
          local at = key == "p" and row + 1 or row
          for i = #register.lines, 1, -1 do table.insert(lines, at, register.lines[i]) end
          row = at
          firstNonBlank()
        else
          if key == "p" and ulen(lines[row]) > 0 then col = col + 1 end
          insertAt(register.text); col = col - 1
        end
      end
    end
  elseif key == "u" then restore(undo, redo, "undo")
  elseif key == "ctrl+r" then restore(redo, undo, "redo")
  elseif key == "n" then find(lastSearch, false)
  elseif key == "N" then find(lastSearch, true)
  elseif key == "/" then
    local q = readCommand("/")
    if q and q ~= "" then lastSearch = q end
    if q then find(lastSearch, false) end
  elseif key == ":" then
    local c = readCommand(":")
    if c then command(c) end
  elseif key == "d" or key == "y" or key == "g" or key == "r" or key == "Z" then
    pending = key; return
  elseif key == "ctrl+c" or key == "interrupt" then
    message, messageColor = "Type  :qa!  and press <Enter> to abandon all changes and exit Vim", T.fg
  elseif key == "escape" then -- nothing to cancel
  end
  count = ""
end

-- ---- insert mode ------------------------------------------------------------------------
local function insert(key, extra)
  local line = lines[row]
  if key == "escape" or key == "ctrl+c" or key == "interrupt" then
    mode = "normal"; col = math.max(0, col - 1)
  elseif key == "enter" then
    lines[row] = usub(line, 1, col)
    table.insert(lines, row + 1, usub(line, col + 1))
    row, col = row + 1, 0
  elseif key == "backspace" then
    if col > 0 then lines[row] = usub(line, 1, col - 1) .. usub(line, col + 1); col = col - 1
    elseif row > 1 then
      col = ulen(lines[row - 1])
      lines[row - 1] = lines[row - 1] .. table.remove(lines, row)
      row = row - 1
    end
  elseif key == "delete" then
    if col < ulen(line) then lines[row] = usub(line, 1, col) .. usub(line, col + 2)
    elseif row < #lines then lines[row] = line .. table.remove(lines, row + 1) end
  elseif key == "left" then col = math.max(0, col - 1)
  elseif key == "right" then col = math.min(ulen(line), col + 1)
  elseif key == "up" then row = math.max(1, row - 1)
  elseif key == "down" then row = math.min(#lines, row + 1)
  elseif key == "home" then col = 0
  elseif key == "end" then col = ulen(line)
  elseif key == "tab" then insertAt("    ")
  elseif key == "paste" then
    local first = true
    for piece in ((extra or "") .. "\n"):gmatch("([^\n]*)\n") do
      if not first then
        local cur = lines[row]
        lines[row] = usub(cur, 1, col)
        table.insert(lines, row + 1, usub(cur, col + 1))
        row, col = row + 1, 0
      end
      insertAt(piece); first = false
    end
  elseif ulen(key) == 1 then insertAt(key)
  end
end

-- ---- main loop ---------------------------------------------------------------------------
local saved = k.event.interruptible
k.event.interruptible = 0 -- Ctrl+C belongs to vim
term.clear()
local okRun, err = pcall(function()
  local full = true
  while running do
    col = math.max(0, math.min(col, lastCol()))
    if scroll() or full then drawAll() end
    drawStatus()
    term.setCursor(gutter() + 1 + col - left, row - top + 1)
    local key, extra = term.readKey(true)
    if mode == "normal" then message, messageColor = nil, nil end
    local prevRow, prevCount = row, #lines
    if mode == "insert" then insert(key, extra) else normal(key, extra) end
    full = row ~= prevRow or #lines ~= prevCount or key == "u" or key == "ctrl+r" or key == ":" or key == "/"
    if not full then drawLine(row) end
  end
end)
k.event.interruptible = saved
term.setBackground(T.bg); term.setForeground(T.fg)
term.clear()
if not okRun then error(err, 0) end
return 0
