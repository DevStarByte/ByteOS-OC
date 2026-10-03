--[[
  rofi [-show run|window] - a launcher for Hyprbyte

  A box in the middle of the screen: type a few letters of a program (they
  need not be next to each other: "sctl" finds systemctl), pick one with
  the arrows and press Enter to open it in a window. Text with spaces runs
  as it is typed ("ping box2"). Tab copies the pick into the line, Esc
  closes the box.

    -show run      programs (Mod+D in Hyprbyte)
    -show window   the open windows, on every workspace (Mod+W)
]]--
local T = term.theme
local args = arg or {}
local hypr = package.loaded["hyprbyte.state"]
if not hypr or not hypr.grab then print("rofi: Hyprbyte 1.2 or newer is not running"); return 1 end
for _, l in ipairs(hypr.layers) do if l.namespace == "rofi" then return 0 end end

local mode = "run"
for i = 1, #args do if args[i] == "-show" then mode = args[i + 1] or mode end end
if mode ~= "run" and mode ~= "window" then print("rofi: no mode " .. tostring(mode)); return 1 end
local HISTORY = (_G.HOME or "/") .. "/.cache/rofi.history"

-- ---- what can be picked ----------------------------------------------------------
local entries = {}
if mode == "run" then
  local seen = {}
  for line in (fs.readAll(HISTORY) or ""):gmatch("[^\n]+") do
    if not seen[line] then seen[line] = true; entries[#entries + 1] = { label = line, recent = true } end
  end
  local names = {}
  for dir in (_G.PATH or "/bin:/usr/bin"):gmatch("[^:]+") do
    for _, f in ipairs(fs.list(dir) or {}) do
      local name = f:match("^(.+)%.lua$")
      if name and not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
  end
  table.sort(names)
  for _, n in ipairs(names) do entries[#entries + 1] = { label = n } end
else
  for n, space in ipairs(hypr.workspaces) do
    for _, win in ipairs(space.list) do
      entries[#entries + 1] = { label = ("%d: %s"):format(n, (win.term and win.term.title) or win.title), id = win.id }
    end
  end
end

-- ---- fuzzy filter --------------------------------------------------------------------
local input, selected, top, shown = "", 1, 1, {}
local function score(label, q)
  if q == "" then return 1 end
  local l, s = label:lower(), q:lower()
  if l:sub(1, #s) == s then return 3 end
  if l:find(s, 1, true) then return 2 end
  local i = 1
  for c in s:gmatch(".") do
    i = l:find(c, i, true)
    if not i then return nil end
    i = i + 1
  end
  return 1
end
local function filter()
  shown = {}
  for _, e in ipairs(entries) do
    local sc = score(e.label, input)
    if sc then shown[#shown + 1] = { e = e, score = sc, order = #shown } end
  end
  table.sort(shown, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.order < b.order
  end)
  selected, top = 1, 1
end
filter()

-- ---- the box --------------------------------------------------------------------------
local layer, done
local function finish()
  done = true
  hypr.removeLayer(layer)
end
local function accept()
  local pick = shown[selected] and shown[selected].e
  finish()
  if mode == "window" then
    if pick then hypr.dispatchers.focuswindow(tostring(pick.id)) end
    return
  end
  local cmd = input
  if pick and not input:find("%s") then cmd = pick.label end
  cmd = cmd:gsub("^%s+", ""):gsub("%s+$", "")
  if cmd == "" then return end
  local lines, keep = { cmd }, {}
  keep[cmd] = true
  for line in (fs.readAll(HISTORY) or ""):gmatch("[^\n]+") do
    if not keep[line] and #lines < 20 then keep[line] = true; lines[#lines + 1] = line end
  end
  if not fs.isDirectory((_G.HOME or "/") .. "/.cache") then fs.makeDirectory((_G.HOME or "/") .. "/.cache") end
  fs.writeAll(HISTORY, table.concat(lines, "\n") .. "\n")
  hypr.dispatchers.exec(cmd)
end

layer = {
  namespace = "rofi", anchor = "overlay",
  place = function(SW, SH)
    local w, h = math.min(56, SW - 4), math.min(14, SH - 4)
    return (SW - w) // 2 + 1, math.max(2, (SH - h) // 3), w, h
  end,
  draw = function(gpu, x, y, w, h)
    local corner = hypr.corners or { "╭", "╮", "╰", "╯" }
    gpu.setBackground(T.surface); gpu.fill(x, y, w, h, " ")
    gpu.setForeground(T.accent)
    gpu.set(x, y, corner[1] .. string.rep("─", w - 2) .. corner[2])
    for i = 1, h - 2 do gpu.set(x, y + i, "│"); gpu.set(x + w - 1, y + i, "│") end
    gpu.set(x, y + h - 1, corner[3] .. string.rep("─", w - 2) .. corner[4])
    gpu.set(x + 2, y, " " .. mode .. " ")
    gpu.setForeground(T.green); gpu.set(x + 2, y + 1, "❯ ")
    gpu.setForeground(T.bright)
    local room = w - 7
    local text = input
    if term.ulen(text) > room then text = term.usub(text, -room) end
    gpu.set(x + 4, y + 1, text .. "▏")
    gpu.setForeground(T.dim); gpu.set(x + 1, y + 2, string.rep("─", w - 2))
    local rows = h - 4
    if selected < top then top = selected end
    if selected >= top + rows then top = selected - rows + 1 end
    for i = 0, rows - 1 do
      local item = shown[top + i]
      if not item then break end
      local label = term.pad(" " .. item.e.label .. (item.e.recent and "  ↺" or ""), w - 2)
      if top + i == selected then gpu.setBackground(T.accent); gpu.setForeground(T.bright)
      else gpu.setBackground(T.surface); gpu.setForeground(T.fg) end
      gpu.set(x + 1, y + 3 + i, label)
    end
    if #shown == 0 then gpu.setForeground(T.muted); gpu.set(x + 2, y + 3, "nothing matches; Enter runs it as typed") end
    gpu.setBackground(T.bg)
  end,
  key = function(ev, _, ch, code)
    if ev ~= "key_down" then return end
    if code == 1 then finish()
    elseif code == 28 or code == 156 then accept()
    elseif code == 200 then selected = math.max(1, selected - 1)
    elseif code == 208 then selected = math.min(math.max(1, #shown), selected + 1)
    elseif code == 15 then if shown[selected] and mode == "run" then input = shown[selected].e.label; filter() end
    elseif code == 14 then input = term.usub(input, 1, -2); filter()
    elseif ch and ch >= 32 and ch ~= 127 then
      input = input .. (unicode and unicode.char or utf8.char)(math.floor(ch)); filter()
    end
  end,
  click = function(_, y)
    local i = top + y - 4
    if shown[i] then selected = i; accept() end
  end,
}
hypr.addLayer(layer)
hypr.grab(layer)
while not done and package.loaded["hyprbyte.state"] == hypr do k.event.pull(0.5) end
if not done then hypr.removeLayer(layer) end
return 0
