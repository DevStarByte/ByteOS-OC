--[[
  /usr/lib/quickshell.lua - Quickshell's widgets and how they are drawn

  A shell file (~/.config/quickshell/shell.lua) returns panels made of
  widgets; see man quickshell. quickshell.env(hypr) is what that file sees,
  quickshell.panels(result) checks what it returned, quickshell.draw and
  quickshell.click do the rest for Hyprbyte's layers.
]]--
local T = term.theme
local ulen, usub = term.ulen, term.usub
local qs = {}

local function color(c, default)
  if type(c) == "number" then return c end
  return T[c] or default
end
local function text(v)
  if type(v) == "function" then
    local ok, r = pcall(v)
    return ok and tostring(r == nil and "" or r) or ("!" .. tostring(r))
  end
  return v == nil and "" or tostring(v)
end
local function percent(part, whole) return math.floor(100 * part / math.max(whole, 1) + 0.5) end

-- ---- the widgets ------------------------------------------------------------------
-- Each kind: label(w, ctx) -> the text it shows, or draw/width/click of its own.
local KINDS = {}

KINDS.Text = { label = function(w) return text(w.props.text) end }
KINDS.Clock = { label = function(w)
  local ok, clock = pcall(require, "clock")
  return ok and clock.date(w.props.format or "%H:%M") or os.date(w.props.format or "%H:%M")
end }
KINDS.Memory = { label = function(w)
  local used = percent(computer.totalMemory() - computer.freeMemory(), computer.totalMemory())
  return (w.props.format or "mem %d%%"):format(used)
end }
KINDS.Energy = { label = function(w)
  if not computer.maxEnergy or computer.maxEnergy() <= 0 then return "" end
  return (w.props.format or "⚡%d%%"):format(percent(computer.energy(), computer.maxEnergy()))
end }
KINDS.ActiveWindow = { label = function(w, ctx)
  local win = ctx.hypr.focused and ctx.hypr.focused()
  if not win then return w.props.empty or "" end
  local t = (win.term and win.term.title) or win.title or ""
  local max = w.props.max or 40
  if ulen(t) > max then t = usub(t, 1, max - 1) .. "…" end
  return t
end }
KINDS.Separator = { label = function(w) return w.props.char or "│" end, defaultColor = "dim" }
KINDS.Spacer = { fill = true, label = function() return "" end }
KINDS.Button = {
  label = function(w) return text(w.props.text) end,
  click = function(w, ctx)
    local on = w.props.onClick
    if type(on) == "function" then on()
    elseif type(on) == "string" and ctx.hypr.dispatchers then ctx.hypr.dispatchers.exec(on) end
  end,
}
-- the output of a command line, run again every `interval` seconds
KINDS.Command = { label = function(w)
  local out = w.output or "…"
  if w.props.format then return (w.props.format):format(out) end
  return out
end }

-- workspace buttons: the active one highlighted, ones with windows bright
KINDS.Workspaces = {
  items = function(w, ctx)
    local spaces = ctx.hypr.workspaces or {}
    local last = w.props.shown or 5
    for i, s in ipairs(spaces) do if #s.list > 0 then last = math.max(last, i) end end
    return last
  end,
  width = function(w, ctx) return 3 * KINDS.Workspaces.items(w, ctx) end,
  draw = function(w, ctx, gpu, x, y, bg)
    local spaces = ctx.hypr.workspaces or {}
    for i = 1, KINDS.Workspaces.items(w, ctx) do
      local active = i == ctx.hypr.active
      local used = spaces[i] and #spaces[i].list > 0
      gpu.setBackground(active and color(w.props.activeColor, T.accent) or bg)
      gpu.setForeground(active and T.bright or used and T.fg or T.dim)
      gpu.set(x + 3 * (i - 1), y, " " .. i .. " ")
    end
  end,
  click = function(w, ctx, dx)
    local n = (dx - 1) // 3 + 1
    if ctx.hypr.dispatchers then ctx.hypr.dispatchers.workspace(tostring(n)) end
  end,
}

-- Row and PanelWindow hold other widgets (the list part of their table)
KINDS.Row = { container = true }
KINDS.PanelWindow = { container = true }

local function make(kind)
  return function(props)
    props = props or {}
    local w = { kind = kind, props = props, children = {} }
    for _, c in ipairs(props) do
      if type(c) ~= "table" or not c.kind then error(kind .. ": item " .. tostring(_) .. " is not a widget", 2) end
      w.children[#w.children + 1] = c
    end
    return w
  end
end

-- ---- layout -----------------------------------------------------------------------
local function widthOf(w, ctx)
  local k = KINDS[w.kind]
  if k.container then
    local n = 0
    for _, c in ipairs(w.children) do
      local cw = widthOf(c, ctx)
      if cw ~= "fill" then n = n + cw end
    end
    return n
  end
  if k.fill then return "fill" end
  if k.width then return k.width(w, ctx) end
  local label = k.label(w, ctx)
  w.cached = label
  return label == "" and 0 or ulen(label) + (w.props.padding or 1) * 2
end

-- lay out a container's children over w columns from x: { widget, x, width }
local function place(container, ctx, x, w, out)
  local fixed, fills = 0, 0
  local widths = {}
  for i, c in ipairs(container.children) do
    local cw = widthOf(c, ctx)
    widths[i] = cw
    if cw == "fill" then fills = fills + 1 else fixed = fixed + cw end
  end
  local spare = math.max(0, w - fixed)
  local cx = x
  for i, c in ipairs(container.children) do
    local cw = widths[i]
    if cw == "fill" then
      cw = spare // fills -- the last one also gets what does not divide
      spare = spare - cw; fills = fills - 1
    end
    if KINDS[c.kind].container then place(c, ctx, cx, cw, out)
    else out[#out + 1] = { widget = c, x = cx, width = cw } end
    cx = cx + cw
  end
  return out
end

function qs.draw(panel, ctx, gpu, x, y, w, h)
  local bg = color(panel.props.color, T.base)
  gpu.setBackground(bg); gpu.fill(x, y, w, h, " ")
  local row = y + (h - 1) // 2
  panel.boxes = place(panel, ctx, x, w, {})
  for _, b in ipairs(panel.boxes) do
    local wd, k = b.widget, KINDS[b.widget.kind]
    local wbg = color(wd.props.bg, bg)
    if k.draw then k.draw(wd, ctx, gpu, b.x, row, wbg)
    elseif b.width > 0 then
      local label = wd.cached or k.label(wd, ctx)
      local pad = string.rep(" ", wd.props.padding or 1)
      gpu.setBackground(wbg)
      gpu.setForeground(color(wd.props.color, color(k.defaultColor, T.fg)))
      gpu.set(b.x, row, usub(pad .. label .. pad, 1, math.max(0, x + w - b.x)))
    end
  end
  gpu.setBackground(T.bg)
end

function qs.click(panel, ctx, x)
  for _, b in ipairs(panel.boxes or {}) do
    if x >= b.x and x < b.x + b.width then
      local k = KINDS[b.widget.kind]
      if k.click then k.click(b.widget, ctx, x - b.x + 1) end
      return true
    end
  end
end

-- every Command widget in a panel (quickshell runs them on their timers)
function qs.commands(w, out)
  out = out or {}
  if w.kind == "Command" then out[#out + 1] = w end
  for _, c in ipairs(w.children) do qs.commands(c, out) end
  return out
end

-- what a shell file sees: the widgets, plus the usual globals
function qs.env(hypr)
  local env = { hypr = hypr, theme = T }
  for kind in pairs(KINDS) do env[kind] = make(kind) end
  local okC, clock = pcall(require, "clock")
  env.clock = okC and clock or nil
  return setmetatable(env, { __index = _G })
end

-- the panels a shell file returned: one PanelWindow or a list of them
function qs.panels(result)
  if type(result) ~= "table" then return nil, "the shell file must return a PanelWindow or a list of them" end
  local list = result.kind and { result } or result
  for i, p in ipairs(list) do
    if type(p) ~= "table" or p.kind ~= "PanelWindow" then return nil, "item " .. i .. " is not a PanelWindow" end
    local a = p.props.anchor or "top"
    if a ~= "top" and a ~= "bottom" then return nil, "anchor must be top or bottom, not " .. tostring(a) end
  end
  if #list == 0 then return nil, "no PanelWindow" end
  return list
end

return qs
