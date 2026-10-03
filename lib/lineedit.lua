--[[
  /lib/lineedit.lua - fish-style interactive line editor

    lineedit.read(opts) -> line, or nil on Ctrl+D at an empty line
      opts.history    earlier lines, oldest first (read only)
      opts.highlight  function(buf) -> { { text, color }, ... }
      opts.suggest    function(buf) -> a full line that starts with buf, or nil
      opts.complete   function(before) -> start, candidates
                        `before` is the text left of the cursor; the word
                        being completed starts at character `start` of it
      opts.prompt     function() that draws the prompt again (after Ctrl+L
                        or a list of completions)

  The prompt is drawn by the caller; the line starts at the cursor and
  scrolls sideways when it gets longer than the screen.

  Keys, as in fish:
    Up / Down        history; with text typed, only lines containing it
    Right / End / ^F at the end of the line, accept the grey suggestion
    Tab              complete; lists the candidates when it is ambiguous
    Home / ^A        start of line      End / ^E   end of line
    ^U / ^K          delete to the start / end of the line
    ^W               delete the word before the cursor
    ^L               clear the screen   ^C         cancel the line
    ^D               on an empty line: end the shell
]]--

local term = require("term")
local T    = term.theme
local gpu  = term.gpu
local ulen, usub = term.ulen, term.usub
local CHAR = utf8 and utf8.charpattern or "[%z\1-\127\194-\244][\128-\191]*"

local lineedit = {}

local function cells(text, color, into)
  for ch in text:gmatch(CHAR) do into[#into + 1] = { ch, color } end
end

local function commonPrefix(list)
  local p = list[1]
  for i = 2, #list do
    local q, n = list[i], 0
    while n < #p and n < #q and p:sub(n + 1, n + 1) == q:sub(n + 1, n + 1) do n = n + 1 end
    p = p:sub(1, n)
  end
  return p
end

-- Print candidates in columns below the line (at most 40 of them).
local function listCandidates(list)
  local W = term.size()
  local width = 0
  for _, c in ipairs(list) do width = math.max(width, ulen(c)) end
  width = width + 2
  local cols = math.max(1, math.floor(W / width))
  local shown = math.min(#list, 40)
  for i = 1, shown do
    term.cwrite(T.muted, term.pad(list[i], width))
    if i % cols == 0 or i == shown then term.write("\n") end
  end
  if #list > shown then term.cwrite(T.muted, ("…and %d more\n"):format(#list - shown)) end
end

local function readLine(opts)
  local W = term.size()
  local history = opts.history or {}
  local buf, pos, off = "", 0, 0
  local startX, startY
  local hidx, search, stash = #history + 1, "", ""
  local final = false

  local function anchor()
    startX, startY = term.getCursor()
    startX = math.min(startX, W)
  end
  anchor()

  local function suggestion()
    if final or buf == "" or pos ~= ulen(buf) or not opts.suggest then return nil end
    local s = opts.suggest(buf)
    if s and #s > #buf and s:sub(1, #buf) == buf then return s end
  end

  local function paint()
    local room = math.max(1, W - startX) -- one column stays free for the cursor
    local line = {}
    if opts.highlight then
      for _, c in ipairs(opts.highlight(buf)) do cells(c[1], c[2], line) end
    else
      cells(buf, T.fg, line)
    end
    local sug = suggestion()
    if sug then cells(sug:sub(#buf + 1), T.dim, line) end
    if pos < off then off = pos end
    if pos > off + room then off = pos - room end

    local oldBg = gpu.setBackground(T.bg)
    gpu.fill(startX, startY, W - startX + 1, 1, " ")
    local x, i, last = startX, off + 1, math.min(#line, off + room)
    while i <= last do
      local color, run = line[i][2], {}
      while i <= last and line[i][2] == color do run[#run + 1] = line[i][1]; i = i + 1 end
      gpu.setForeground(color)
      gpu.set(x, startY, table.concat(run))
      x = x + #run
    end
    gpu.setForeground(T.fg)
    gpu.setBackground(oldBg)
    term.setCursor(startX + pos - off, startY)
    return sug
  end

  local function set(s) buf, pos = s, ulen(s) end
  local function edited() hidx = #history + 1 end
  local function insert(s)
    buf = usub(buf, 1, pos) .. s .. usub(buf, pos + 1)
    pos = pos + ulen(s)
    edited()
  end

  -- Step through history; with text typed, only lines containing it count.
  local function step(dir)
    if hidx == #history + 1 then stash, search = buf, buf end
    local i = hidx + dir
    while i >= 1 and i <= #history do
      local h = history[i]
      if h ~= buf and (search == "" or h:find(search, 1, true)) then break end
      i = i + dir
    end
    if i < 1 then return end
    if i > #history then hidx = #history + 1; set(stash); return end
    hidx = i
    set(history[i])
  end

  local finish -- defined below

  local function complete()
    local before = usub(buf, 1, pos)
    local start, list = opts.complete(before)
    if not list or #list == 0 then return end
    local word = usub(before, start)
    local head = usub(before, 1, start - 1)
    local function replace(with)
      buf = head .. with .. usub(buf, pos + 1)
      pos = ulen(head .. with)
    end
    if #list == 1 then
      replace(list[1] .. (list[1]:sub(-1) == "/" and "" or " "))
      return
    end
    local common = commonPrefix(list)
    if #common > #word then
      replace(common)
    else
      finish(); final = false
      listCandidates(list)
      if opts.prompt then opts.prompt() end
      anchor()
      off = 0
    end
  end

  -- Leave the whole line on screen, wrapped instead of scrolled sideways,
  -- so it reads correctly in the scrollback.
  function finish(tail)
    final = true
    gpu.fill(startX, startY, W - startX + 1, 1, " ")
    term.setCursor(startX, startY)
    if opts.highlight then
      for _, c in ipairs(opts.highlight(buf)) do term.cwrite(c[2], c[1]) end
    else
      term.write(buf)
    end
    if tail then term.cwrite(T.muted, tail) end
    term.write("\n")
  end

  while true do
    local sug = paint()
    local key, extra = term.readKey(true)

    if key == "enter" then
      finish()
      return buf
    elseif key == "ctrl+c" or key == "interrupt" then
      finish("^C")
      return ""
    elseif key == "ctrl+d" then
      if buf == "" then term.write("\n"); return nil end
      buf = usub(buf, 1, pos) .. usub(buf, pos + 2); edited()
    elseif key == "backspace" then
      if pos > 0 then buf = usub(buf, 1, pos - 1) .. usub(buf, pos + 1); pos = pos - 1 end
      edited()
    elseif key == "delete" then
      buf = usub(buf, 1, pos) .. usub(buf, pos + 2); edited()
    elseif key == "left" then
      pos = math.max(0, pos - 1)
    elseif key == "right" or key == "end" or key == "ctrl+e" or key == "ctrl+f" then
      if sug then set(sug); edited()
      elseif key == "right" or key == "ctrl+f" then pos = math.min(ulen(buf), pos + 1)
      else pos = ulen(buf) end
    elseif key == "home" or key == "ctrl+a" then
      pos = 0
    elseif key == "ctrl+u" then
      buf = usub(buf, pos + 1); pos = 0; edited()
    elseif key == "ctrl+k" then
      buf = usub(buf, 1, pos); edited()
    elseif key == "ctrl+w" then
      local before = usub(buf, 1, pos):gsub("%s*[^%s]*$", "")
      buf = before .. usub(buf, pos + 1); pos = ulen(before); edited()
    elseif key == "ctrl+l" then
      term.clear()
      if opts.prompt then opts.prompt() end
      anchor(); off = 0
    elseif key == "up" then
      step(-1)
    elseif key == "down" then
      step(1)
    elseif key == "tab" then
      if opts.complete then complete() end
    elseif key == "paste" then
      insert(((extra or ""):match("^[^\r\n]*")))
    elseif type(key) == "string" and ulen(key) == 1 then
      insert(key)
    end
  end
end

-- While the line is being typed, Ctrl+C cancels the line instead of
-- stopping the program the editor runs in (e.g. a nested shell).
function lineedit.read(opts)
  local ev = _G.kernel.event
  local saved = ev.interruptible
  ev.interruptible = 0
  local res = table.pack(pcall(readLine, opts))
  ev.interruptible = saved
  if not res[1] then error(res[2], 0) end
  return res[2]
end

return lineedit
