--[[
  figlet - big letters out of ordinary characters

    figlet ByteOS          ____        _        ___  ____
                          | __ ) _   _| |_ ___ / _ \/ ___|
                          |  _ \| | | | __/ _ \ | | \___ \
                          | |_) | |_| | ||  __/ |_| |___) |
                          |____/ \__, |\__\___|\___/|____/
                                 |___/
    echo hi | figlet      one figlet line per line of input
    -f FONT               another font: a name in /usr/share/figlet or a path
    -w WIDTH              wrap at WIDTH columns (default: the screen)
    -c                    centre every line
    -k                    letters side by side, touching but not merged
    -W                    letters at their full width

  Without text it reads its input, one figlet line per input line. Reads
  FIGlet 2 fonts (.flf); the Standard font by Glenn Chappell & Ian Chai
  comes with it. Letters merge ("smush") as the font asks, like FIGlet.
]]--
local args = arg or {}
local fontName, width, center, mode = "standard", nil, false, nil
local words = {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-f" or a == "-w" then
    i = i + 1
    if not args[i] then term.write("figlet: " .. a .. " needs a value\n"); return 2 end
    if a == "-f" then fontName = args[i] else width = tonumber(args[i]) end
    if a == "-w" and not width then term.write("figlet: -w needs a number\n"); return 2 end
  elseif a == "-c" then center = true
  elseif a == "-k" then mode = "kern"
  elseif a == "-W" then mode = "full"
  elseif a:match("^%-.") then term.write("figlet: unknown option " .. a .. "\n"); return 2
  else words[#words + 1] = a end
  i = i + 1
end
width = width or (term.size()) or 80

-- ---- the font ----------------------------------------------------------------------------
local path = fontName:find("/") and shell.normalize(fontName)
  or "/usr/share/figlet/" .. fontName:gsub("%.flf$", "") .. ".flf"
local raw = fs.readAll(path)
if not raw then term.write("figlet: no font " .. path .. "\n"); return 1 end
raw = raw:gsub("\r", "")
local lines = {}
for l in (raw .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
local hard, height, oldLayout, comments = lines[1]:match("^flf2a(.)%s+(%d+)%s+%d+%s+%d+%s+(%-?%d+)%s+(%d+)")
if not hard then term.write("figlet: " .. path .. " is not a FIGlet font\n"); return 1 end
height, oldLayout, comments = tonumber(height), tonumber(oldLayout), tonumber(comments)

-- the characters 32 to 126, in order; each row ends with an end mark ("@")
local glyphs, n = {}, 2 + comments
for code = 32, 126 do
  local g = {}
  for r = 1, height do
    local l = lines[n] or ""
    local mark = l:sub(-1)
    g[r] = l:gsub(mark:gsub("%p", "%%%0") .. "+$", "")
    n = n + 1
  end
  glyphs[code] = g
end

-- smushing as FIGlet does it: 1 equal, 2 underscore, 4 hierarchy, 8 pairs,
-- 16 big X, 32 hardblanks; 0 means kerning, -1 full width
local rules = oldLayout > 0 and oldLayout or 0
if mode == "kern" then rules = 0 end
if mode == "full" or (not mode and oldLayout < 0) then mode = "full" end

local function bit(v, b) return math.floor(v / b) % 2 == 1 end
local CLASSES = { "|", "/\\", "[]", "{}", "()", "<>" }
local function class(c)
  for idx, s in ipairs(CLASSES) do if s:find(c, 1, true) then return idx end end
end
local PAIRS = { ["[]"] = "|", ["]["] = "|", ["{}"] = "|", ["}{"] = "|", ["()"] = "|", [")("] = "|" }
local BIGX = { ["/\\"] = "|", ["\\/"] = "Y", ["><"] = "X" }

-- the character l and r merge into, or nil when they don't
local function smush(l, r, lw, rw)
  if l == " " then return r end
  if r == " " then return l end
  if rules == 0 or lw < 2 or rw < 2 then return nil end
  if l == hard or r == hard then
    if bit(rules, 32) and l == hard and r == hard then return l end
    return nil
  end
  if bit(rules, 1) and l == r then return l end
  if bit(rules, 2) then
    if l == "_" and ("|/\\[]{}()<>"):find(r, 1, true) then return r end
    if r == "_" and ("|/\\[]{}()<>"):find(l, 1, true) then return l end
  end
  if bit(rules, 4) then
    local cl, cr = class(l), class(r)
    if cl and cr and cl ~= cr then return cl > cr and l or r end
  end
  if bit(rules, 8) and PAIRS[l .. r] then return PAIRS[l .. r] end
  if bit(rules, 16) and BIGX[l .. r] then return BIGX[l .. r] end
  return nil
end

-- how far glyph g can slide into the rows
local function overlap(rows, g, lastWidth)
  if mode == "full" then return 0 end
  local gw = #g[1]
  local amt = gw
  for r = 1, height do
    local line, cur = rows[r], g[r]
    local p = #line
    while p > 0 and line:sub(p, p) == " " do p = p - 1 end
    local lead = #(cur:match("^ *"))
    local a = lead + #line - p
    local ch1, ch2 = line:sub(p, p), cur:sub(lead + 1, lead + 1)
    if p > 0 and ch2 ~= "" and smush(ch1, ch2, lastWidth, gw) then a = a + 1 end
    if a < amt then amt = a end
  end
  return amt
end

local function addGlyph(rows, g, lastWidth)
  local amt = overlap(rows, g, lastWidth)
  local out = {}
  for r = 1, height do
    local line, cur = rows[r], g[r]
    local keep = #line - amt
    local mid = {}
    -- overlapping columns merge; the ones left of the line's start drop off
    for k = 1, amt do
      local col = keep + k
      if col >= 1 then
        local l, c = line:sub(col, col), cur:sub(k, k)
        mid[#mid + 1] = (l == "" and c) or smush(l, c, lastWidth, #g[1]) or c
      end
    end
    out[r] = line:sub(1, math.max(0, keep)) .. table.concat(mid) .. cur:sub(amt + 1)
  end
  return out
end

-- ---- layout ------------------------------------------------------------------------------
local function empty() local t = {} for r = 1, height do t[r] = "" end return t end

local function flush(rows)
  if #rows[1] == 0 then return end
  local w = 0
  for r = 1, height do
    rows[r] = rows[r]:gsub(hard:gsub("%p", "%%%0"), " "):gsub(" +$", "")
    w = math.max(w, #rows[r])
  end
  local pad = center and (" "):rep(math.max(0, (width - w) // 2)) or ""
  for r = 1, height do
    if rows[r] ~= "" then term.write(pad .. rows[r] .. "\n") elseif r < height then term.write("\n") end
  end
end

local function render(text)
  text = text:gsub("\t", " "):gsub("[^\32-\126]", "?")
  local rows, last = empty(), 0
  local function wide(t)
    local w = 0
    for r = 1, height do w = math.max(w, #t[r]) end
    return w
  end
  -- characters onto the line; with wrap, a new line when one passes the last column
  local function put(chars, wrap)
    for c in chars:gmatch(".") do
      local g = glyphs[c:byte()]
      local before = rows
      rows = addGlyph(rows, g, last)
      if wrap and wide(rows) >= width and wide(before) > 0 then
        flush(before)
        rows = c == " " and empty() or addGlyph(empty(), g, 0)
      end
      last = #g[1]
    end
  end
  for word, space in text:gmatch("(%S*)(%s*)") do
    if word == "" and space == "" then break end
    -- a word that does not fit starts a new line (and breaks if it is longer)
    local saved, savedLast = rows, last
    put(word, false)
    if wide(rows) >= width then
      rows, last = saved, savedLast
      if wide(rows) > 0 then flush(rows); rows, last = empty(), 0 end
      put(word, true)
    end
    put(space, true)
  end
  flush(rows)
end

if #words > 0 then
  render(table.concat(words, " "))
elseif stdin and not stdin.isTerminal then
  for l in (stdin.read("a") or ""):gmatch("[^\n]+") do render(l) end
else
  term.write("usage: figlet [-f FONT] [-w WIDTH] [-c] [-k] [-W] TEXT\n")
  return 2
end
return 0
