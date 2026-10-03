--[[
  tools/test/fterm.lua - the terminal for tests: a W x H character grid
  (colours remembered per cell) instead of a GPU. Keys for term.readKey
  come from term.feed{...}, lines for term.read from term.answers{...}.
]]--
local W, H = tonumber(os.getenv("TW") or 80), tonumber(os.getenv("TH") or 200)
local grid, colors = {}, {}
local cx, cy, fg = 1, 1, 0xD8DEE9
local CHAR = utf8.charpattern
local function blank() for y = 1, H do grid[y], colors[y] = {}, {} for x = 1, W do grid[y][x] = " " end end end
blank()
local function scroll() table.remove(grid, 1); table.remove(colors, 1); grid[H], colors[H] = {}, {}; for x = 1, W do grid[H][x] = " " end end
local function newline() cx = 1; cy = cy + 1; if cy > H then scroll(); cy = H end end
local function put(x, y, s)
  for ch in s:gmatch(CHAR) do if x >= 1 and x <= W then grid[y][x] = ch; colors[y][x] = fg end x = x + 1 end
end

local theme = setmetatable({ bg = 0, fg = 0xD8DEE9, dim = 0x4A5568, muted = 0x8A96A8, red = 0xF0605A,
  green = 0x5FD068, blue = 0x6CB6FF, cyan = 0x4FD1C5, yellow = 0xE8C061, magenta = 0xC792EA,
  accent = 0x1793D1, bright = 0xFFFFFF, err = 0xF0605A, warn = 0xE8C061, ok = 0x5FD068 },
  { __index = function() return 0 end })
local NAMES = {}
for k, v in pairs(theme) do NAMES[v] = NAMES[v] or k end

local bg = 0
local gpu = {
  setBackground = function(c) local o = bg; bg = c; return o end,
  setForeground = function(c) local o = fg; fg = c; return o end,
  getForeground = function() return fg end, getBackground = function() return bg end,
  fill = function(x, y, w, h, ch)
    for yy = math.max(1, y), math.min(H, y + h - 1) do
      for xx = math.max(1, x), math.min(W, x + w - 1) do grid[yy][xx] = ch; colors[yy][xx] = nil end
    end
  end,
  set = function(x, y, s) if y >= 1 and y <= H then put(x, y, s) end end,
  get = function(x, y) return (grid[y] or {})[x] or " ", (colors[y] or {})[x] or fg, bg end,
  copy = function(x, y, w, h, tx, ty)
    local rows = {}
    for yy = y, y + h - 1 do
      rows[yy] = {}
      for xx = x, x + w - 1 do rows[yy][xx] = { (grid[yy] or {})[xx], (colors[yy] or {})[xx] } end
    end
    for yy = y, y + h - 1 do
      for xx = x, x + w - 1 do
        local c, ny, nx = rows[yy][xx], yy + ty, xx + tx
        if c[1] and grid[ny] and nx >= 1 and nx <= W then grid[ny][nx] = c[1]; colors[ny][nx] = c[2] end
      end
    end
  end,
  getResolution = function() return W, H end,
  getDepth = function() return 8 end,
}

local keys, answers = {}, {}
local term = {
  theme = theme, gpu = gpu, width = W, depth = 8,
  size = function() return W, H end,
  getCursor = function() return cx, cy end,
  setCursor = function(x, y) cx, cy = x, y end,
  setForeground = function(c) fg = c end, setBackground = function() end,
  ulen = function(s) return utf8.len(s) end,
  usub = function(s, i, j)
    local n = utf8.len(s); j = j or n
    if i < 0 then i = math.max(1, n + i + 1) end
    if j < 0 then j = n + j + 1 end
    if i > j or i > n then return "" end
    local a = utf8.offset(s, i); local b = utf8.offset(s, j + 1)
    return s:sub(a, (b or #s + 1) - 1)
  end,
  pad = function(s, w) return s .. string.rep(" ", math.max(0, w - utf8.len(s))) end,
  clear = function() blank(); cx, cy = 1, 1 end,
  readKey = function() local k = table.remove(keys, 1); if not k then error("out of keys", 0) end return k end,
  read = function() return table.remove(answers, 1) end, -- nil when none is queued (like ^D)
}
function term.write(s)
  s = tostring(s)
  for ch in s:gmatch(CHAR) do
    if ch == "\n" then newline() elseif ch == "\r" then cx = 1
    else if cx > W then newline() end; put(cx, cy, ch); cx = cx + 1 end
  end
end
function term.clearLine() for x = cx, W do grid[cy][x] = " "; colors[cy][x] = nil end end
function term.cwrite(c, s) local o = fg; fg = c; term.write(s); fg = o end

-- keys: list; a plain string longer than one char is typed letter by letter
-- unless it is a key name in <angle brackets>
function term.feed(list)
  for _, k in ipairs(list) do
    local name = k:match("^<(.+)>$")
    if name then keys[#keys + 1] = name
    else for ch in k:gmatch(CHAR) do keys[#keys + 1] = ch end end
  end
end
function term.answers(list) for _, a in ipairs(list) do answers[#answers + 1] = a end end

-- the screen as text, trailing spaces removed
function term.screen()
  local out = {}
  for y = 1, cy do out[#out + 1] = (table.concat(grid[y]):gsub("%s+$", "")) end
  return table.concat(out, "\n")
end

function term.dump(from, to)
  for y = from or 1, to or cy do
    local line = table.concat(grid[y]):gsub("%s+$", "")
    if line ~= "" or y <= cy then print(("%2d|%s"):format(y, line)) end
  end
end
-- colours of the cells in row y as "name:text" runs
function term.runs(y)
  local out, cur, buf = {}, nil, {}
  for x = 1, W do
    local c = colors[y][x]
    if c ~= cur then
      if #buf > 0 and cur then out[#out + 1] = (NAMES[cur] or "?") .. ":" .. table.concat(buf) end
      cur, buf = c, {}
    end
    buf[#buf + 1] = grid[y][x]
  end
  if #buf > 0 and cur then out[#out + 1] = (NAMES[cur] or "?") .. ":" .. table.concat(buf) end
  return table.concat(out, " | ")
end
return term
