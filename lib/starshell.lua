--[[
  /lib/starshell.lua  -  StarShell
  A friendly, fish-flavoured shell with a Starship-style segmented prompt.

  Features:
    * Multi-segment prompt with powerline-ish glyphs (user, host, dir, status).
    * Live syntax highlighting:
        - command in green if found in PATH or built-in, red otherwise
        - quoted strings in cyan
        - flags (--foo / -x) in yellow
        - the rest in default white
    * Autosuggestions from history shown in dim grey past the cursor.
        - Right Arrow / End accepts the suggestion
    * Up / Down arrow walks history.
    * Tab completion for commands (first word) and paths (subsequent words).
    * Ctrl-style line nav: Home / End / Left / Right / Backspace.
    * Persistent history at  ~/.starshell_history  (best-effort).

  StarShell delegates command execution to the regular ByteShell so all your
  existing built-ins, /bin/*.lua programs and pacman just work.
]]--

local k     = _G.kernel
local fs    = k.fs
local term  = require("term")
local shell = require("shell")

local star = {}

-- ---- Colours -----------------------------------------------------------
local C = {
  fg       = 0xFFFFFF,
  dim      = 0x666666,
  cmd_ok   = 0x55FF55,
  cmd_bad  = 0xFF5555,
  string   = 0x55FFFF,
  flag     = 0xFFCC55,
  number   = 0xCC99FF,
  -- prompt segments (fg / bg pairs)
  seg_user_bg  = 0x66CCFF, seg_user_fg  = 0x000000,
  seg_host_bg  = 0x4488CC, seg_host_fg  = 0xFFFFFF,
  seg_dir_bg  = 0x333333, seg_dir_fg   = 0xFFCC55,
  seg_arrow_ok  = 0x55FF55,
  seg_arrow_bad = 0xFF5555,
}

-- ---- History -----------------------------------------------------------
local history       = {}
local HISTFILE      = nil    -- set in star.repl()
local HISTMAX       = 500

local function loadHistory()
  HISTFILE = (_G.HOME or "/home/root") .. "/.starshell_history"
  if not fs.exists(HISTFILE) then return end
  local data = fs.readAll(HISTFILE) or ""
  for line in data:gmatch("[^\n]+") do history[#history+1] = line end
end

local function saveHistory()
  if not HISTFILE then return end
  local first = math.max(1, #history - HISTMAX + 1)
  local out = {}
  for i = first, #history do out[#out+1] = history[i] end
  pcall(fs.writeAll, HISTFILE, table.concat(out, "\n") .. "\n")
end

local function pushHistory(line)
  if line == "" then return end
  if history[#history] == line then return end
  history[#history+1] = line
  saveHistory()
end

-- ---- Helpers -----------------------------------------------------------
local BUILTINS = { cd=true, exit=true, export=true, set=true, help=true }

local function commandExists(name)
  if name == nil or name == "" then return false end
  if BUILTINS[name] then return true end
  return shell.resolveBin(name) ~= nil
end

local function basename(p)
  return p:match("([^/]+)$") or p
end

local function dirname(p)
  if p == "" then return "." end
  if not p:find("/") then return "." end
  return p:match("^(.*)/") or "/"
end

local function shorten(path)
  local home = _G.HOME
  if home and path:sub(1, #home) == home then
    path = "~" .. path:sub(#home + 1)
  end
  return path
end

-- Find the longest history entry that starts with `prefix`. Newest first.
local function suggest(prefix)
  if prefix == "" then return nil end
  for i = #history, 1, -1 do
    local h = history[i]
    if h ~= prefix and #h > #prefix and h:sub(1, #prefix) == prefix then
      return h
    end
  end
  return nil
end

-- ---- Tokeniser for highlighting ----------------------------------------
-- Returns a list of {text=..., color=...} chunks.
local function highlight(line)
  local out = {}
  local i, n = 1, #line
  local sawCommand = false

  local function emitCommand(s)
    table.insert(out, {
      text  = s,
      color = commandExists(s) and C.cmd_ok or C.cmd_bad,
    })
  end

  local function emitWord(s)
    if not sawCommand then
      emitCommand(s); sawCommand = true; return
    end
    local color = C.fg
    if s:sub(1,1) == "-" then color = C.flag
    elseif tonumber(s) then  color = C.number
    end
    table.insert(out, { text = s, color = color })
  end

  while i <= n do
    local ch = line:sub(i, i)
    if ch == " " or ch == "\t" then
      local j = i
      while j <= n and (line:sub(j,j) == " " or line:sub(j,j) == "\t") do j = j + 1 end
      table.insert(out, { text = line:sub(i, j - 1), color = C.fg })
      i = j
    elseif ch == "\"" or ch == "'" then
      local j = line:find(ch, i + 1, true) or (n + 1)
      table.insert(out, { text = line:sub(i, math.min(j, n)), color = C.string })
      sawCommand = true
      i = j + 1
    else
      local j = line:find("[%s]", i) or (n + 1)
      emitWord(line:sub(i, j - 1))
      i = j
    end
  end
  return out
end

-- ---- Prompt rendering --------------------------------------------------
-- Segmented "starship"-ish prompt. Returns the column the cursor lands on.
local function drawPrompt(lastStatus)
  local user = _G.USER or "root"
  local host = _G.HOSTNAME or "byteos"
  local pwd  = shorten(_G.PWD or "/")

  local function segment(text, fg, bg, nextBg)
    term.setBackground(bg); term.setForeground(fg)
    term.write(" " .. text .. " ")
    if nextBg then
      term.setBackground(nextBg); term.setForeground(bg)
      term.write("\u{e0b0}")  -- powerline right arrow; falls back to ?
    else
      term.setBackground(0x000000); term.setForeground(bg)
      term.write("\u{e0b0}")
    end
  end

  -- A version with safe ASCII fallback (OC fonts often lack 0xE0B0).
  local function asciiSeg(text, fg, bg, nextBg)
    term.setBackground(bg); term.setForeground(fg)
    term.write(" " .. text .. " ")
    term.setBackground(nextBg or 0x000000); term.setForeground(bg)
    term.write(">")
  end

  local seg = asciiSeg  -- safe default; OC default font has no powerline glyphs

  seg(user,  C.seg_user_fg, C.seg_user_bg, C.seg_host_bg)
  seg(host,  C.seg_host_fg, C.seg_host_bg, C.seg_dir_bg)
  seg(pwd,   C.seg_dir_fg,  C.seg_dir_bg,  nil)

  term.setBackground(0x000000); term.setForeground(C.fg)
  term.write("\n")

  -- Second line: status arrow (green if last command succeeded, red if not)
  local arrowColor = (lastStatus == 0) and C.seg_arrow_ok or C.seg_arrow_bad
  term.setForeground(arrowColor)
  local promptStr = (user == "root") and "# " or "> "
  term.write(promptStr)
  term.setForeground(C.fg)
  return select(1, term.getCursor())  -- column where typed text starts
end

-- ---- Tab completion ----------------------------------------------------
local function listDir(path)
  local out = {}
  for _, n in ipairs(fs.list(path) or {}) do out[#out+1] = n end
  return out
end

local function pathsForCompletion(prefix, isFirstWord)
  local results = {}
  if isFirstWord and not prefix:find("/") then
    -- Complete commands from PATH + builtins
    for b in pairs(BUILTINS) do
      if b:sub(1, #prefix) == prefix then results[#results+1] = b end
    end
    for dir in (_G.PATH or "/bin"):gmatch("[^:]+") do
      for _, name in ipairs(listDir(dir)) do
        local clean = name:gsub("/$", ""):gsub("%.lua$", "")
        if clean:sub(1, #prefix) == prefix then results[#results+1] = clean end
      end
    end
  else
    -- Complete a path
    local dir, base
    if prefix == "" then
      dir, base = _G.PWD or "/", ""
    elseif prefix:sub(-1) == "/" then
      dir, base = prefix, ""
    else
      dir  = prefix:find("/") and dirname(prefix) or (_G.PWD or "/")
      base = basename(prefix)
    end
    if dir:sub(1,1) ~= "/" then dir = (_G.PWD or "/") .. "/" .. dir end
    dir = shell.normalize(dir)
    for _, name in ipairs(listDir(dir)) do
      local clean = name:gsub("/$", "")
      if clean:sub(1, #base) == base then
        local full = (prefix:find("/") and (dirname(prefix) .. "/" .. clean)) or clean
        if fs.isDirectory(dir .. "/" .. clean) then full = full .. "/" end
        results[#results+1] = full
      end
    end
  end
  table.sort(results)
  return results
end

local function commonPrefix(list)
  if #list == 0 then return "" end
  local p = list[1]
  for i = 2, #list do
    local q = list[i]
    local n = 0
    while n < #p and n < #q and p:sub(n+1, n+1) == q:sub(n+1, n+1) do n = n + 1 end
    p = p:sub(1, n)
    if p == "" then return "" end
  end
  return p
end

-- Replace the last whitespace-separated word in `buf` with `replacement`.
local function replaceLastWord(buf, replacement)
  local i = #buf
  while i > 0 and not buf:sub(i, i):match("%s") do i = i - 1 end
  return buf:sub(1, i) .. replacement
end

local function lastWord(buf)
  return buf:match("(%S*)$") or ""
end

-- ---- Line editor -------------------------------------------------------
local function readLine(promptCol, lastStatus)
  local W, H = term.size()
  local buf, cur = "", 0
  local startX, startY = promptCol, select(2, term.getCursor())
  local histIdx = #history + 1
  local stash = ""

  local function paint()
    -- clear from prompt to end of line
    term.setCursor(startX, startY)
    term.gpu.fill(startX, startY, W - startX + 1, 1, " ")
    term.setBackground(0x000000)
    -- highlighted buffer
    local chunks = highlight(buf)
    for _, c in ipairs(chunks) do
      term.setForeground(c.color); term.write(c.text)
    end
    -- ghost suggestion
    local sug = suggest(buf)
    local sugTail = ""
    if sug then
      sugTail = sug:sub(#buf + 1)
      term.setForeground(C.dim); term.write(sugTail)
    end
    term.setForeground(C.fg)
    -- place real cursor right after the typed buffer
    local cursorX = startX + cur
    if cursorX > W then cursorX = W end
    term.setCursor(cursorX, startY)
    return sug
  end

  while true do
    local sug = paint()
    local key = term.readKey()

    if key == "enter" then
      term.setCursor(startX + #buf, startY)
      term.write("\n")
      return buf

    elseif key == "interrupt" then
      term.setCursor(startX + #buf, startY); term.write("^C\n")
      return ""

    elseif key == "backspace" then
      if cur > 0 then
        buf = buf:sub(1, cur - 1) .. buf:sub(cur + 1)
        cur = cur - 1
      end

    elseif key == "left"  then if cur > 0 then cur = cur - 1 end
    elseif key == "right" then
      if cur < #buf then
        cur = cur + 1
      elseif sug then
        buf = sug; cur = #buf
      end

    elseif key == "home" then cur = 0
    elseif key == "end" then
      if cur < #buf then cur = #buf
      elseif sug then buf = sug; cur = #buf end

    elseif key == "up" then
      if histIdx > 1 then
        if histIdx == #history + 1 then stash = buf end
        histIdx = histIdx - 1
        buf = history[histIdx]; cur = #buf
      end

    elseif key == "down" then
      if histIdx <= #history then
        histIdx = histIdx + 1
        if histIdx == #history + 1 then buf = stash else buf = history[histIdx] end
        cur = #buf
      end

    elseif key == "tab" then
      local words = {}
      for w in buf:gmatch("%S+") do words[#words+1] = w end
      local prefix      = lastWord(buf)
      local isFirst     = #words <= 1 and not buf:match("%s$")
      local matches     = pathsForCompletion(prefix, isFirst)
      if #matches == 1 then
        buf = replaceLastWord(buf, matches[1]); cur = #buf
      elseif #matches > 1 then
        local cp = commonPrefix(matches)
        if cp ~= "" and cp ~= prefix then
          buf = replaceLastWord(buf, cp); cur = #buf
        else
          -- list candidates below prompt
          term.setCursor(startX + #buf, startY); term.write("\n")
          term.setForeground(C.dim)
          for i, m in ipairs(matches) do
            term.write(m)
            if i % 4 == 0 then term.write("\n") else term.write("  ") end
          end
          term.setForeground(C.fg); term.write("\n")
          -- redraw prompt
          drawPrompt(lastStatus)
          startX, startY = select(1, term.getCursor()), select(2, term.getCursor())
        end
      end

    elseif type(key) == "string" and #key == 1 then
      buf = buf:sub(1, cur) .. key .. buf:sub(cur + 1)
      cur = cur + 1
    end
  end
end

-- ---- Welcome -----------------------------------------------------------
local function welcome()
  term.setForeground(C.cmd_ok)
  term.write("Welcome to StarShell")
  term.setForeground(C.dim); term.write(" - the friendly shell\n")
  term.setForeground(C.fg)
  term.write("Type "); term.setForeground(C.flag); term.write("help")
  term.setForeground(C.fg); term.write(" for help, ")
  term.setForeground(C.flag); term.write("exit"); term.setForeground(C.fg)
  term.write(" to leave.\n\n")
end

-- ---- REPL --------------------------------------------------------------
function star.repl()
  loadHistory()
  welcome()
  local lastStatus = 0
  while true do
    local promptCol = drawPrompt(lastStatus)
    local line = readLine(promptCol, lastStatus)
    line = (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      pushHistory(line)
      local ok, rc = pcall(shell.execute, line)
      if not ok then
        if rc == "__exit__" then return end
        term.setForeground(C.cmd_bad)
        term.write("error: " .. tostring(rc) .. "\n")
        term.setForeground(C.fg)
        lastStatus = 1
      else
        lastStatus = tonumber(rc) or 0
      end
    end
  end
end

return star
