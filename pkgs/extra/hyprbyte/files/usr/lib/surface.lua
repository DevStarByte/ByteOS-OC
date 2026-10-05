--[[
  /usr/lib/surface.lua - a drawing surface for a window (hyprbyte)

  Draws like a GPU (set, fill, copy, get, colours), but into a buffer of
  its own; while shown it also draws onto its place on the real screen.
  A window manager puts a terminal on one (tty.new(surface)) for each
  window, so programs in a window draw into it and never next to it.

    local s = surface.new(gpu, x, y, w, h)   at x, y on the screen, w x h big
    s.show(true | false)                     draw on the screen or only keep
    s.place(x, y, w, h [, drop])             move or resize; drop rows from the
                                             top (to keep the cursor's line)
    s.redraw()                               draw everything again
    s.cover(rects)                           screen rects {x, y, w, h} above the
                                             window (overlay layers): it never
                                             draws there, only into its buffer
    s.touched                                true once it drew on the screen

  The buffer is a string per row for the characters and one byte per cell
  for each colour (an index into the colours used so far), which keeps a
  window's memory small.
]]--
local term = require("term")
local ulen, usub = term.ulen, term.usub

local surface = {}

-- the parts of columns sx..sx+n-1 of screen row sy that no rect covers:
-- out(from, to) for each, in screen columns
function surface.spans(rects, sx, sy, n, out)
  local a, b = sx, sx + n - 1
  local cuts
  for _, r in ipairs(rects) do
    if sy >= r[2] and sy < r[2] + r[4] and r[1] <= b and r[1] + r[3] - 1 >= a then
      cuts = cuts or {}
      cuts[#cuts + 1] = { math.max(a, r[1]), math.min(b, r[1] + r[3] - 1) }
    end
  end
  if not cuts then return out(a, b) end
  table.sort(cuts, function(p, q) return p[1] < q[1] end)
  local col = a
  for _, c in ipairs(cuts) do
    if c[1] > col then out(col, c[1] - 1) end
    col = math.max(col, c[2] + 1)
  end
  if col <= b then out(col, b) end
end

-- does a rect cover any cell of the block x1..x2, y1..y2 (screen)?
function surface.covered(rects, x1, y1, x2, y2)
  for _, r in ipairs(rects) do
    if r[1] <= x2 and r[1] + r[3] - 1 >= x1 and r[2] <= y2 and r[2] + r[4] - 1 >= y1 then return true end
  end
  return false
end

function surface.new(real, x, y, w, h)
  local s = {}
  local ox, oy, W, H = x, y, w, h
  local shown = false
  local fg, bg = 0xFFFFFF, 0x000000
  local colors, index = {}, {}         -- index byte -> colour, colour -> byte
  local text, fgs, bgs = {}, {}, {}    -- per row
  local covers = {}                    -- screen rects of the layers above

  local function idx(c)
    local i = index[c]
    if not i then
      if #colors >= 255 then return string.char(255) end -- out of slots: reuse the last
      colors[#colors + 1] = c
      i = string.char(#colors)
      index[c] = i
    end
    return i
  end

  local function blank(row, width)
    width = width or W
    text[row] = string.rep(" ", width)
    fgs[row] = string.rep(idx(fg), width)
    bgs[row] = string.rep(idx(bg), width)
  end
  for row = 1, H do blank(row) end

  -- put n characters (str) with colour bytes f, b at column x of row y
  local function store(x0, y0, str, n, f, b)
    text[y0] = usub(text[y0], 1, x0 - 1) .. str .. usub(text[y0], x0 + n)
    fgs[y0] = fgs[y0]:sub(1, x0 - 1) .. f .. fgs[y0]:sub(x0 + n)
    bgs[y0] = bgs[y0]:sub(1, x0 - 1) .. b .. bgs[y0]:sub(x0 + n)
  end

  -- columns a..b of a row onto the screen, in runs of one colour, around the covers
  local function paintRow(row, a, b)
    local t, f, bb = text[row], fgs[row], bgs[row]
    surface.spans(covers, ox + (a or 1) - 1, oy + row - 1, (b or W) - (a or 1) + 1, function(s1, s2)
      local c1, c2 = s1 - ox + 1, s2 - ox + 1
      local start = c1
      for i = c1 + 1, c2 + 1 do
        if i > c2 or f:byte(i) ~= f:byte(start) or bb:byte(i) ~= bb:byte(start) then
          real.setForeground(colors[f:byte(start)] or 0xFFFFFF)
          real.setBackground(colors[bb:byte(start)] or 0)
          real.set(ox + start - 1, oy + row - 1, usub(t, start, i - 1))
          start = i
        end
      end
    end)
  end
  -- is any cell of the block x1..x2, y1..y2 (surface) under a cover?
  local function hidden(x1, y1, x2, y2)
    return #covers > 0 and surface.covered(covers, ox + x1 - 1, oy + y1 - 1, ox + x2 - 1, oy + y2 - 1)
  end

  function s.redraw()
    if not shown then return end
    local of, ob = real.getForeground and real.getForeground(), real.getBackground and real.getBackground()
    for row = 1, H do paintRow(row) end
    if of then real.setForeground(of) end
    if ob then real.setBackground(ob) end
  end

  function s.show(on)
    shown = on and true or false
    if shown then s.redraw() end
  end
  function s.isShown() return shown end
  function s.cover(rects) covers = rects or {} end

  function s.place(nx, ny, nw, nh, drop)
    drop = math.max(0, math.min(drop or 0, H))
    for _ = 1, drop do
      table.remove(text, 1); table.remove(fgs, 1); table.remove(bgs, 1)
    end
    local f, b = idx(fg), idx(bg)
    for row = 1, nh do
      if not text[row] then
        blank(row, nw)
      elseif nw < W then
        text[row] = usub(text[row], 1, nw); fgs[row] = fgs[row]:sub(1, nw); bgs[row] = bgs[row]:sub(1, nw)
      elseif nw > W then
        text[row] = text[row] .. string.rep(" ", nw - W)
        fgs[row] = fgs[row] .. string.rep(f, nw - W); bgs[row] = bgs[row] .. string.rep(b, nw - W)
      end
    end
    for row = nh + 1, #text do text[row], fgs[row], bgs[row] = nil, nil, nil end
    ox, oy, W, H = nx, ny, nw, nh
    for row = 1, H do if not text[row] then blank(row) end end
    s.redraw()
  end

  -- ---- the GPU's calls ------------------------------------------------------
  function s.getResolution() return W, H end
  s.maxResolution = s.getResolution
  function s.setResolution() return false end
  function s.getDepth() return real.getDepth and real.getDepth() or 8 end
  s.maxDepth = s.getDepth
  function s.setDepth() return false end
  function s.setPaletteColor() end
  function s.getPaletteColor(i) return real.getPaletteColor and real.getPaletteColor(i) end
  function s.bind() return true end
  function s.getScreen() return real.getScreen and real.getScreen() end

  function s.setForeground(c) local old = fg; fg = c; return old end
  function s.setBackground(c) local old = bg; bg = c; return old end
  function s.getForeground() return fg end
  function s.getBackground() return bg end

  function s.set(x0, y0, str, vertical)
    str = tostring(str)
    if vertical then
      local i = 0
      for ch in str:gmatch(utf8.charpattern) do s.set(x0, y0 + i, ch); i = i + 1 end
      return true
    end
    if y0 < 1 or y0 > H or str == "" then return true end
    if x0 < 1 then str = usub(str, 2 - x0); x0 = 1 end
    if x0 > W then return true end
    local n = ulen(str)
    if x0 + n - 1 > W then str = usub(str, 1, W - x0 + 1); n = W - x0 + 1 end
    if n <= 0 then return true end
    store(x0, y0, str, n, idx(fg):rep(n), idx(bg):rep(n))
    if shown then
      real.setForeground(fg); real.setBackground(bg)
      if not hidden(x0, y0, x0 + n - 1, y0) then real.set(ox + x0 - 1, oy + y0 - 1, str)
      else
        surface.spans(covers, ox + x0 - 1, oy + y0 - 1, n, function(s1, s2)
          real.set(s1, oy + y0 - 1, usub(str, s1 - ox - x0 + 2, s2 - ox - x0 + 2))
        end)
      end
      s.touched = true
    end
    return true
  end

  function s.fill(x0, y0, w0, h0, ch)
    local x1, y1 = math.max(1, x0), math.max(1, y0)
    local x2, y2 = math.min(W, x0 + w0 - 1), math.min(H, y0 + h0 - 1)
    if x2 < x1 or y2 < y1 then return true end
    ch = usub(tostring(ch or " "), 1, 1)
    local n = x2 - x1 + 1
    local row, f, b = ch:rep(n), idx(fg):rep(n), idx(bg):rep(n)
    for yy = y1, y2 do store(x1, yy, row, n, f, b) end
    if shown then
      real.setForeground(fg); real.setBackground(bg)
      if not hidden(x1, y1, x2, y2) then real.fill(ox + x1 - 1, oy + y1 - 1, n, y2 - y1 + 1, ch)
      else
        for yy = y1, y2 do
          surface.spans(covers, ox + x1 - 1, oy + yy - 1, n, function(s1, s2)
            real.fill(s1, oy + yy - 1, s2 - s1 + 1, 1, ch)
          end)
        end
      end
      s.touched = true
    end
    return true
  end

  function s.copy(x0, y0, w0, h0, tx, ty)
    local x1, y1 = math.max(1, x0), math.max(1, y0)
    local x2, y2 = math.min(W, x0 + w0 - 1), math.min(H, y0 + h0 - 1)
    if x2 < x1 or y2 < y1 then return true end
    local n, parts = x2 - x1 + 1, {}
    for yy = y1, y2 do
      parts[yy] = { usub(text[yy], x1, x2), fgs[yy]:sub(x1, x2), bgs[yy]:sub(x1, x2) }
    end
    local inside = true
    for yy = y1, y2 do
      local p, dy, dx = parts[yy], yy + ty, x1 + tx
      if dy >= 1 and dy <= H and dx >= 1 and dx + n - 1 <= W then
        store(dx, dy, p[1], n, p[2], p[3])
      else
        inside = false -- partly off the surface: keep what lands on it
        for i = 1, n do
          local cx = dx + i - 1
          if dy >= 1 and dy <= H and cx >= 1 and cx <= W then
            store(cx, dy, usub(p[1], i, i), 1, p[2]:sub(i, i), p[3]:sub(i, i))
          end
        end
      end
    end
    if shown then
      s.touched = true
      -- the screen's copy would move a layer's cells into the window (or the
      -- window's onto a layer): then paint the copied cells from the buffer
      if inside and not hidden(x1, y1, x2, y2) and not hidden(x1 + tx, y1 + ty, x2 + tx, y2 + ty) then
        real.copy(ox + x1 - 1, oy + y1 - 1, n, y2 - y1 + 1, tx, ty)
      else
        local of, ob = real.getForeground and real.getForeground(), real.getBackground and real.getBackground()
        for yy = math.max(1, y1 + ty), math.min(H, y2 + ty) do
          paintRow(yy, math.max(1, x1 + tx), math.min(W, x2 + tx))
        end
        if of then real.setForeground(of) end
        if ob then real.setBackground(ob) end
      end
    end
    return true
  end

  function s.get(x0, y0)
    if x0 < 1 or x0 > W or y0 < 1 or y0 > H then return nil, "index out of bounds" end
    return usub(text[y0], x0, x0), colors[fgs[y0]:byte(x0)], colors[bgs[y0]:byte(x0)]
  end

  -- the text of row y (tests, screenshots)
  function s.line(y0) return text[y0] end

  return s
end

return surface
