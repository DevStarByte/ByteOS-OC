-- edit - full-screen text editor (nano-flavoured)
--   ^S save   ^Q quit   ^K cut line   ^U paste line   ^G go to line
local T = term.theme
local gpu = term.gpu
local ulen, usub = term.ulen, term.usub
local W, H = term.size()

local args = arg or {}
if #args == 0 then shell.err("edit", "usage: edit <file>"); return 1 end
local name = args[1]
local path = shell.normalize(name)
if k.fs.isDirectory(path) then shell.err("edit", name .. " is a directory"); return 1 end

local lines = {}
local isNew = not k.fs.exists(path)
if not isNew then
  local data = (k.fs.readAll(path) or ""):gsub("\r\n", "\n")
  for ln in (data .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = ln end
  if #lines > 1 and lines[#lines] == "" then lines[#lines] = nil end
end
if #lines == 0 then lines[1] = "" end

local row, col = 1, 0        -- cursor: line index, characters before cursor
local top, left = 1, 0       -- scroll offsets (left applies to the cursor line only, like nano)
local modified = false
local clip                   -- cut buffer (list of lines)
local message, messageColor  -- transient status message
local VIEW_H = H - 2         -- rows between title bar and help bar
local isLua = path:match("%.lua$") ~= nil

-- ---- Lua syntax highlighting --------------------------------------------
local KEYWORDS = {}
for w in ([[and break do else elseif end false for function goto if in local
  nil not or repeat return then true until while]]):gmatch("%a+") do KEYWORDS[w] = true end

-- Split a line into { text, colour } chunks.
local function highlight(s)
  if not isLua then return { { s, T.fg } } end
  local out, i, n = {}, 1, #s
  local function push(t, c) if t ~= "" then out[#out + 1] = { t, c } end end
  while i <= n do
    local c = s:sub(i, i)
    if s:sub(i, i + 1) == "--" then
      push(s:sub(i), T.muted); break
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n and s:sub(j, j) ~= c do
        if s:sub(j, j) == "\\" then j = j + 1 end
        j = j + 1
      end
      push(s:sub(i, j), T.green); i = j + 1
    elseif s:sub(i, i + 1) == "[[" then
      local j = s:find("]]", i + 2, true) or n
      push(s:sub(i, j + 1), T.green); i = j + 2
    elseif c:match("%d") then
      local j = s:find("[^%w%.]", i) or n + 1
      push(s:sub(i, j - 1), T.orange); i = j
    elseif c:match("[%a_]") then
      local j = s:find("[^%w_]", i) or n + 1
      local word = s:sub(i, j - 1)
      push(word, KEYWORDS[word] and T.magenta or T.fg); i = j
    else
      local j = s:find("[%w_\"'%-%[]", i + 1) or n + 1
      if j == i then j = i + 1 end
      push(s:sub(i, j - 1), T.blue); i = j
    end
  end
  return out
end

-- ---- Drawing ---------------------------------------------------------------
local function gutterWidth() return math.max(3, #tostring(#lines)) + 1 end

local function drawTitle()
  gpu.setBackground(T.accent); gpu.setForeground(T.on_accent)
  gpu.fill(1, 1, W, 1, " ")
  gpu.set(2, 1, "edit")
  local title = name .. (modified and " *" or "") .. (isNew and " (new)" or "")
  gpu.set(math.max(8, math.floor((W - ulen(title)) / 2) + 1), 1, usub(title, 1, W - 16))
  local pos = ("%d:%d"):format(row, col + 1)
  gpu.set(W - #pos, 1, pos)
end

local HELP = { { "^S", "Save" }, { "^Q", "Quit" }, { "^K", "Cut" }, { "^U", "Paste" }, { "^G", "Go to" } }
local function drawHelp()
  gpu.setBackground(T.raised)
  gpu.fill(1, H, W, 1, " ")
  if message then
    gpu.setForeground(messageColor or T.fg)
    gpu.set(2, H, usub(message, 1, W - 2))
    return
  end
  local x = 2
  for _, h in ipairs(HELP) do
    if x + #h[1] + #h[2] + 1 > W then break end
    gpu.setForeground(T.accent); gpu.set(x, H, h[1])
    gpu.setForeground(T.fg); gpu.set(x + #h[1] + 1, H, h[2])
    x = x + #h[1] + #h[2] + 4
  end
end

local function drawLine(i)
  local y = i - top + 2
  if y < 2 or y > H - 1 then return end
  local gw = gutterWidth()
  gpu.setBackground(T.bg)
  gpu.fill(1, y, W, 1, " ")
  local line = lines[i]
  if not line then
    gpu.setForeground(T.dim); gpu.set(gw - 1, y, "~")
    return
  end
  gpu.setForeground(i == row and T.fg or T.dim)
  gpu.set(1, y, ("%" .. (gw - 1) .. "d"):format(i))
  -- draw the visible slice of the highlighted line
  local x, skip, room = gw + 1, (i == row) and left or 0, W - gw
  for _, chunk in ipairs(highlight(line)) do
    local t = chunk[1]
    local len = ulen(t)
    if skip >= len then
      skip = skip - len
    else
      t = usub(t, skip + 1); skip = 0
      t = usub(t, 1, room - (x - gw - 1))
      if t ~= "" then
        gpu.setForeground(chunk[2]); gpu.set(x, y, t)
        x = x + ulen(t)
      end
      if x > W then break end
    end
  end
end

local function drawAll()
  for i = top, top + VIEW_H - 1 do drawLine(i) end
end

-- Keep the cursor inside the viewport. Returns true if the view scrolled
-- vertically (needs a full repaint); horizontal scrolling only affects the
-- cursor line, which is repainted anyway.
local function scrollToCursor()
  local scrolled = false
  if row < top then top = row; scrolled = true end
  if row >= top + VIEW_H then top = row - VIEW_H + 1; scrolled = true end
  local room = W - gutterWidth() - 1
  if col < left then left = col end
  if col >= left + room then left = col - room + 1 end
  return scrolled
end

local function placeCursor()
  term.setCursor(gutterWidth() + 1 + col - left, row - top + 2)
end

-- ---- Prompts in the help bar -------------------------------------------
local function prompt(question)
  gpu.setBackground(T.raised); gpu.fill(1, H, W, 1, " ")
  gpu.setForeground(T.bright); gpu.set(2, H, question)
  term.setCursor(3 + ulen(question), H)
  gpu.setBackground(T.raised); gpu.setForeground(T.bright)
  local answer = term.read()
  gpu.setBackground(T.bg)
  return answer
end

local function save()
  local data = table.concat(lines, "\n") .. "\n"
  local ok, err = k.fs.writeAll(path, data)
  if ok then
    modified, isNew = false, false
    message, messageColor = ("Wrote %d lines to %s"):format(#lines, name), T.ok
  else
    message, messageColor = "Could not save: " .. tostring(err), T.err
  end
end

-- ---- Main loop -----------------------------------------------------------
term.clear()
drawAll()
local running = true
while running do
  local prevRow = row
  if scrollToCursor() then drawAll() end
  drawTitle(); drawHelp()
  placeCursor()
  local key, extra = term.readKey(true)
  message = nil
  local full = false
  local line = lines[row]

  if key == "ctrl+q" or key == "ctrl+x" then
    if modified then
      local a = (prompt("Save changes before closing? (y/n/c)") or "c"):lower()
      if a == "y" then save(); running = modified
      elseif a == "n" then running = false end
      if running then full = true end
    else
      running = false
    end
  elseif key == "ctrl+s" then
    save()
  elseif key == "ctrl+g" then
    local n = tonumber(prompt("Go to line:"))
    if n then row = math.max(1, math.min(#lines, math.floor(n))); col = 0 end
    full = true
  elseif key == "ctrl+k" then
    clip = { table.remove(lines, row) }
    if #lines == 0 then lines[1] = "" end
    row = math.min(row, #lines); col = 0
    modified, full = true, true
  elseif key == "ctrl+u" then
    if clip then
      for i = #clip, 1, -1 do table.insert(lines, row, clip[i]) end
      modified, full = true, true
    end
  elseif key == "up" then row = math.max(1, row - 1)
  elseif key == "down" then row = math.min(#lines, row + 1)
  elseif key == "left" then
    if col > 0 then col = col - 1
    elseif row > 1 then row = row - 1; col = ulen(lines[row]) end
  elseif key == "right" then
    if col < ulen(line) then col = col + 1
    elseif row < #lines then row = row + 1; col = 0 end
  elseif key == "home" then col = 0
  elseif key == "end" then col = ulen(line)
  elseif key == "pageup" then row = math.max(1, row - VIEW_H)
  elseif key == "pagedown" then row = math.min(#lines, row + VIEW_H)
  elseif key == "enter" then
    local indent = line:match("^%s*")
    if #indent > col then indent = indent:sub(1, col) end
    lines[row] = usub(line, 1, col)
    table.insert(lines, row + 1, indent .. usub(line, col + 1))
    row, col = row + 1, ulen(indent)
    modified, full = true, true
  elseif key == "backspace" then
    if col > 0 then
      lines[row] = usub(line, 1, col - 1) .. usub(line, col + 1)
      col = col - 1; modified = true
    elseif row > 1 then
      col = ulen(lines[row - 1])
      lines[row - 1] = lines[row - 1] .. line
      table.remove(lines, row)
      row = row - 1
      modified, full = true, true
    end
  elseif key == "delete" then
    if col < ulen(line) then
      lines[row] = usub(line, 1, col) .. usub(line, col + 2); modified = true
    elseif row < #lines then
      lines[row] = line .. table.remove(lines, row + 1)
      modified, full = true, true
    end
  elseif key == "tab" then
    lines[row] = usub(line, 1, col) .. "  " .. usub(line, col + 1)
    col = col + 2; modified = true
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
      col = col + ulen(piece)
      first = false
    end
    modified, full = true, true
  elseif ulen(key) == 1 then
    lines[row] = usub(line, 1, col) .. key .. usub(line, col + 1)
    col = col + 1; modified = true
  end

  col = math.min(col, ulen(lines[row]))
  if row ~= prevRow then left = 0 end
  if scrollToCursor() or full then
    drawAll()
  else
    -- only the touched lines need repainting (keeps typing fast on low tiers)
    drawLine(row)
    if prevRow ~= row then drawLine(prevRow) end
  end
end

term.clear()
return 0
