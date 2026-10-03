--[[
  nano [-l] <file> - a small text editor in the style of GNU nano

  Type to write; the bottom two rows show the shortcuts (^ is Ctrl):
    ^O Write Out   ^S Save        ^X Exit (asks to save)
    ^W Where Is    ^K Cut line    ^U Paste       ^C Location
    ^T Go To Line  ^R Read File   ^A / ^E start / end of line
    ^Y / ^V page up / down        ^G Help
  Several ^K in a row cut several lines; ^U pastes them all.

    -l   line numbers
]]--
local T = term.theme
local gpu = term.gpu
local ulen, usub = term.ulen, term.usub
local W, H = term.size()

local args = arg or {}
local numbers, name = false, nil
for _, a in ipairs(args) do
  if a == "-l" or a == "--linenumbers" then numbers = true else name = a end
end
if not name then term.write("usage: nano [-l] <file>\n"); return 1 end
local path = shell.normalize(name)
if fs.isDirectory(path) then term.write("nano: " .. name .. " is a directory\n"); return 1 end

local lines, isNew = {}, not fs.exists(path)
if not isNew then
  local data = (fs.readAll(path) or ""):gsub("\r\n", "\n")
  for ln in (data .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = ln end
  if #lines > 1 and lines[#lines] == "" then lines[#lines] = nil end
end
if #lines == 0 then lines[1] = "" end

local row, col, top, left = 1, 0, 1, 0
local modified, cut, lastKey, lastSearch = false, {}, nil, nil
local status, statusColor
local VIEW_TOP, VIEW_H = 2, H - 4 -- title, text, status line, two shortcut rows

local function gutter() return numbers and (#tostring(#lines) + 1) or 0 end

-- ---- drawing -----------------------------------------------------------------------
local function drawTitle()
  gpu.setBackground(T.fg); gpu.setForeground(T.bg)
  gpu.fill(1, 1, W, 1, " ")
  gpu.set(3, 1, "GNU nano 2.0 (ByteOS)")
  local title = isNew and ("New Buffer: " .. name) or name
  gpu.set(math.max(26, (W - ulen(title)) // 2 + 1), 1, usub(title, 1, W - 38))
  if modified then gpu.set(W - 9, 1, "Modified") end
  gpu.setBackground(T.bg)
end

local SHORTCUTS = {
  { { "^G", "Help" }, { "^O", "Write Out" }, { "^W", "Where Is" }, { "^K", "Cut" }, { "^C", "Location" } },
  { { "^X", "Exit" }, { "^R", "Read File" }, { "^T", "Go To Line" }, { "^U", "Paste" }, { "^S", "Save" } },
}
local function drawBottom()
  gpu.setBackground(T.bg); gpu.fill(1, H - 2, W, 3, " ")
  if status then
    local text = "[ " .. status .. " ]"
    gpu.setBackground(statusColor or T.fg); gpu.setForeground(T.bg)
    gpu.set(math.max(1, (W - ulen(text)) // 2 + 1), H - 2, usub(text, 1, W))
    gpu.setBackground(T.bg)
  end
  local cell = W // 5
  for r, list in ipairs(SHORTCUTS) do
    for i, s in ipairs(list) do
      local x = 1 + (i - 1) * cell
      gpu.setBackground(T.fg); gpu.setForeground(T.bg); gpu.set(x, H - 2 + r, s[1])
      gpu.setBackground(T.bg); gpu.setForeground(T.fg); gpu.set(x + 3, H - 2 + r, usub(s[2], 1, cell - 4))
    end
  end
end

local function drawLine(i)
  local y = VIEW_TOP + i - top
  if y < VIEW_TOP or y >= VIEW_TOP + VIEW_H then return end
  gpu.setBackground(T.bg); gpu.fill(1, y, W, 1, " ")
  local line = lines[i]
  if not line then return end
  local g = gutter()
  if numbers then gpu.setForeground(T.dim); gpu.set(1, y, ("%" .. (g - 1) .. "d"):format(i)) end
  local skip = (i == row) and left or 0 -- like nano, only the cursor's line scrolls sideways
  local text = usub(line, skip + 1, skip + W - g)
  gpu.setForeground(T.fg); gpu.set(g + 1, y, text)
  if skip > 0 then gpu.setForeground(T.accent); gpu.set(g + 1, y, "<") end
  if ulen(line) > skip + W - g then gpu.setForeground(T.accent); gpu.set(W, y, ">") end
end
local function drawAll() for i = top, top + VIEW_H - 1 do drawLine(i) end end

local function scroll()
  local moved = false
  if row < top then top = row; moved = true end
  if row >= top + VIEW_H then top = row - VIEW_H + 1; moved = true end
  local room = W - gutter() - 1
  if col < left then left = col end
  if col >= left + room then left = col - room + 1 end
  return moved
end

-- a question on the status line; returns the answer (nil: cancelled)
local function ask(question, default)
  gpu.setBackground(T.fg); gpu.setForeground(T.bg)
  gpu.fill(1, H - 2, W, 1, " ")
  gpu.set(1, H - 2, question .. ": ")
  term.setCursor(ulen(question) + 3, H - 2)
  term.setBackground(T.fg); term.setForeground(T.bg)
  local answer = term.read({ default = default })
  term.setBackground(T.bg); term.setForeground(T.fg)
  if answer == nil then return nil end
  if answer == "" then return default end
  return answer
end

-- Y / N / ^C on the status line
local function yesNo(question)
  gpu.setBackground(T.fg); gpu.setForeground(T.bg)
  gpu.fill(1, H - 2, W, 1, " ")
  gpu.set(1, H - 2, question)
  gpu.setBackground(T.bg); gpu.setForeground(T.fg)
  gpu.fill(1, H - 1, W, 2, " ")
  gpu.set(2, H - 1, "Y Yes"); gpu.set(2, H, "N No"); gpu.set(16, H - 1, "^C Cancel")
  while true do
    local key = term.readKey(true)
    if key == "y" or key == "Y" then return "y" end
    if key == "n" or key == "N" then return "n" end
    if key == "ctrl+c" or key == "interrupt" or key == "escape" then return nil end
  end
end

local function write(target)
  local ok, err = fs.writeAll(shell.normalize(target), table.concat(lines, "\n") .. "\n")
  if not ok then status, statusColor = "Error writing " .. target .. ": " .. tostring(err), T.red; return false end
  if shell.normalize(target) == path then modified, isNew = false, false end
  status, statusColor = ("Wrote %d line%s"):format(#lines, #lines == 1 and "" or "s"), nil
  return true
end

local function writeOut()
  local target = ask("File Name to Write", name)
  if not target then status = "Cancelled"; return false end
  if target ~= name and shell.normalize(target) ~= path then
    name, path = target, shell.normalize(target)
  end
  return write(name)
end

local function search()
  local q = ask("Search" .. (lastSearch and (" [" .. lastSearch .. "]") or ""), nil)
  if q == nil and not lastSearch then status = "Cancelled"; return end
  q = (q == nil or q == "") and lastSearch or q
  lastSearch = q
  local n = #lines
  for step = 0, n do
    local i = (row - 1 + step) % n + 1
    local from = (step == 0) and (col + 2) or 1
    local hit = lines[i]:find(q, from, true)
    if hit then
      if step == n and i == row then status = "This is the only occurrence" end
      row, col = i, ulen(lines[i]:sub(1, hit - 1))
      return
    end
  end
  status = '"' .. q .. '" not found'
end

local HELP = [[
 Main nano help text

 Type to insert text; the arrows, Home, End, PgUp and PgDn move.
 ^ means Ctrl.

 ^O   Write Out: save, asking for the file name
 ^S   Save under the current name
 ^X   Exit (asks whether to save a modified buffer)
 ^W   Where Is: search forward (Enter alone: the last search)
 ^K   Cut the current line; more ^K in a row cut more lines
 ^U   Paste what was cut
 ^C   Location: where the cursor is
 ^T   Go To Line
 ^R   Read File: insert a file at the cursor
 ^A   Start of the line        ^E   End of the line
 ^Y   Previous page            ^V   Next page
 ^G   This help

 Press any key to go back.]]

local function help()
  gpu.setBackground(T.bg); gpu.setForeground(T.fg)
  gpu.fill(1, 2, W, H - 1, " ")
  local y = 2
  for l in (HELP .. "\n"):gmatch("([^\n]*)\n") do
    if y > H then break end
    gpu.set(1, y, usub(l, 1, W)); y = y + 1
  end
  term.readKey(true)
end

-- ---- main loop ------------------------------------------------------------------------
local saved = k.event.interruptible
k.event.interruptible = 0 -- ^C is nano's Location, not "stop the program"
term.clear()
status = isNew and "New File" or ("Read %d line%s"):format(#lines, #lines == 1 and "" or "s")
drawAll()
local running = true
local okRun, err = pcall(function()
  while running do
    local prevRow = row
    if scroll() then drawAll() end
    drawTitle(); drawBottom()
    term.setCursor(gutter() + 1 + col - left, VIEW_TOP + row - top)
    local key, extra = term.readKey(true)
    status = nil
    local full, line = false, lines[row]
    if key ~= "ctrl+k" then lastKey = key end

    if key == "ctrl+x" then
      if modified then
        local a = yesNo("Save modified buffer?  ")
        if a == "y" then running = not writeOut()
        elseif a == "n" then running = false
        else status = "Cancelled" end
      else
        running = false
      end
      full = true
    elseif key == "ctrl+o" then writeOut(); full = true
    elseif key == "ctrl+s" then write(name)
    elseif key == "ctrl+w" then search(); full = true
    elseif key == "ctrl+g" then help(); full = true
    elseif key == "ctrl+c" or key == "interrupt" then
      local chars, before = 0, 0
      for i, l in ipairs(lines) do
        chars = chars + ulen(l) + 1
        if i < row then before = before + ulen(l) + 1 end
      end
      local function pct(a, b) return math.floor(100 * a / math.max(b, 1)) end
      status = ("line %d/%d (%d%%), col %d/%d (%d%%), char %d/%d (%d%%)"):format(
        row, #lines, pct(row, #lines), col + 1, ulen(line) + 1, pct(col + 1, ulen(line) + 1),
        before + col + 1, chars, pct(before + col + 1, chars))
    elseif key == "ctrl+t" then
      local n = tonumber(ask("Enter line number", nil) or "")
      if n then row = math.max(1, math.min(#lines, math.floor(n))); col = 0 end
      full = true
    elseif key == "ctrl+r" then
      local f = ask("File to insert", nil)
      if f and fs.exists(shell.normalize(f)) and not fs.isDirectory(shell.normalize(f)) then
        local add = {}
        for ln in ((fs.readAll(shell.normalize(f)) or ""):gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do add[#add + 1] = ln end
        if #add > 1 and add[#add] == "" then add[#add] = nil end
        for i = #add, 1, -1 do table.insert(lines, row, add[i]) end
        modified = true
        status = ("Read %d line%s"):format(#add, #add == 1 and "" or "s")
      elseif f then
        status, statusColor = "File \"" .. f .. "\" not found", T.red
      end
      full = true
    elseif key == "ctrl+k" then
      if lastKey ~= "ctrl+k" then cut = {} end
      lastKey = "ctrl+k"
      cut[#cut + 1] = table.remove(lines, row)
      if #lines == 0 then lines[1] = "" end
      row = math.min(row, #lines); col = 0
      modified, full = true, true
    elseif key == "ctrl+u" then
      for i = #cut, 1, -1 do table.insert(lines, row, cut[i]) end
      if #cut > 0 then row = row + #cut; col = 0; modified, full = true, true end
    elseif key == "ctrl+a" or key == "home" then col = 0
    elseif key == "ctrl+e" or key == "end" then col = ulen(line)
    elseif key == "ctrl+y" or key == "pageup" then row = math.max(1, row - VIEW_H)
    elseif key == "ctrl+v" or key == "pagedown" then row = math.min(#lines, row + VIEW_H)
    elseif key == "up" then row = math.max(1, row - 1)
    elseif key == "down" then row = math.min(#lines, row + 1)
    elseif key == "left" then
      if col > 0 then col = col - 1 elseif row > 1 then row = row - 1; col = ulen(lines[row]) end
    elseif key == "right" then
      if col < ulen(line) then col = col + 1 elseif row < #lines then row = row + 1; col = 0 end
    elseif key == "enter" then
      lines[row] = usub(line, 1, col)
      table.insert(lines, row + 1, usub(line, col + 1))
      row, col = row + 1, 0
      modified, full = true, true
    elseif key == "backspace" then
      if col > 0 then
        lines[row] = usub(line, 1, col - 1) .. usub(line, col + 1); col = col - 1; modified = true
      elseif row > 1 then
        col = ulen(lines[row - 1])
        lines[row - 1] = lines[row - 1] .. table.remove(lines, row)
        row = row - 1; modified, full = true, true
      end
    elseif key == "delete" then
      if col < ulen(line) then
        lines[row] = usub(line, 1, col) .. usub(line, col + 2); modified = true
      elseif row < #lines then
        lines[row] = line .. table.remove(lines, row + 1); modified, full = true, true
      end
    elseif key == "tab" then
      lines[row] = usub(line, 1, col) .. "    " .. usub(line, col + 1); col = col + 4; modified = true
    elseif key == "paste" then
      local first = true
      for piece in ((extra or "") .. "\n"):gmatch("([^\n]*)\n") do
        if not first then
          local cur = lines[row]
          lines[row] = usub(cur, 1, col)
          table.insert(lines, row + 1, usub(cur, col + 1))
          row, col = row + 1, 0
        end
        local cur = lines[row]
        lines[row] = usub(cur, 1, col) .. piece .. usub(cur, col + 1)
        col = col + ulen(piece); first = false
      end
      modified, full = true, true
    elseif ulen(key) == 1 then
      lines[row] = usub(line, 1, col) .. key .. usub(line, col + 1); col = col + 1; modified = true
    end

    col = math.min(col, ulen(lines[row]))
    if row ~= prevRow then left = 0 end
    if scroll() or full then drawAll()
    else drawLine(row); if prevRow ~= row then drawLine(prevRow) end end
  end
end)
k.event.interruptible = saved
term.setBackground(T.bg); term.setForeground(T.fg)
term.clear()
if not okRun then error(err, 0) end
return 0
