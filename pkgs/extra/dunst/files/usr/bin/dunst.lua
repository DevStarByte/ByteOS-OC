--[[
  dunst - shows notifications as pop-ups in Hyprbyte's top right corner

  Anything sent with notify-send (or the notify library, e.g. ByteNet
  messages) appears there; a click closes one, critical ones stay until
  then. dunstctl shows the history and turns do-not-disturb on and off.
  Start it with Hyprbyte: exec-once = dunst. Settings: ~/.config/dunst/dunstrc
  (else /etc/dunst/dunstrc): width, timeout, max.
]]--
local notify = require("notify")
local T = term.theme
local hypr = package.loaded["hyprbyte.state"]
if not hypr or not hypr.grab then
  print("dunst: Hyprbyte 1.2 or newer is not running (exec-once = dunst)")
  return 1
end
if notify.running() then print("dunst: a notification daemon is already running"); return 1 end

local conf = { width = 36, timeout = 6, max = 3 }
for _, path in ipairs({ "/etc/dunst/dunstrc", (_G.HOME or "/") .. "/.config/dunst/dunstrc" }) do
  for line in (fs.readAll(path) or ""):gmatch("[^\r\n]+") do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key then conf[key] = tonumber(value) or value end
  end
end

local d = { shown = {}, waiting = {}, paused = false }
package.loaded["dunst.state"] = d
local COLOR = { low = T.dim, normal = T.accent, critical = T.red }

-- the body cut into lines of `w` columns, two at most
local function wrap(text, w)
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    if line == "" then line = word
    elseif term.ulen(line) + 1 + term.ulen(word) <= w then line = line .. " " .. word
    else lines[#lines + 1] = line; line = word end
  end
  if line ~= "" then lines[#lines + 1] = line end
  if #lines > 2 then lines = { lines[1], term.usub(lines[2], 1, w - 1) .. "…" } end
  for i, l in ipairs(lines) do lines[i] = term.usub(l, 1, w) end
  return lines
end
local function height(n, w) return 3 + #wrap(n.body, w - 4) end

local layer
layer = {
  namespace = "dunst", anchor = "overlay",
  place = function(SW)
    local w = math.min(conf.width, SW - 2)
    local h = 0
    for _, n in ipairs(d.shown) do h = h + height(n, w) end
    return SW - w, 2, w, h
  end,
  draw = function(gpu, x, y, w)
    local cy = y
    local corner = hypr.corners or { "╭", "╮", "╰", "╯" }
    for _, n in ipairs(d.shown) do
      local body = wrap(n.body, w - 4)
      local h = 3 + #body
      local c = COLOR[n.urgency] or T.accent
      gpu.setBackground(T.surface); gpu.fill(x, cy, w, h, " ")
      gpu.setForeground(c)
      gpu.set(x, cy, corner[1] .. string.rep("─", w - 2) .. corner[2])
      for i = 1, h - 2 do gpu.set(x, cy + i, "│"); gpu.set(x + w - 1, cy + i, "│") end
      gpu.set(x, cy + h - 1, corner[3] .. string.rep("─", w - 2) .. corner[4])
      if n.app ~= "" then gpu.setForeground(T.muted); gpu.set(x + 2, cy, " " .. term.usub(n.app, 1, w - 6) .. " ") end
      gpu.setForeground(T.bright)
      gpu.set(x + 2, cy + 1, term.usub(n.summary, 1, w - 4))
      gpu.setForeground(T.fg)
      for i, l in ipairs(body) do gpu.set(x + 2, cy + 1 + i, l) end
      n.top, n.bottom = cy, cy + h - 1
      cy = cy + h
    end
    gpu.setBackground(T.bg)
  end,
  click = function(_, y)
    local abs = y + 1 -- the layer starts at row 2
    for i, n in ipairs(d.shown) do
      if n.top and abs >= n.top and abs <= n.bottom then table.remove(d.shown, i); break end
    end
    hypr.relayout = true
  end,
}
hypr.addLayer(layer)

local function show(n)
  local t = n.timeout
  if t == nil then t = n.urgency == "critical" and 0 or conf.timeout end
  n.expires = t > 0 and computer.uptime() + t or nil
  table.insert(d.shown, 1, n) -- the newest on top
  while #d.shown > conf.max do d.waiting[#d.waiting + 1] = table.remove(d.shown) end
  hypr.refresh()
end

local function receive(n)
  if d.paused and n.urgency ~= "critical" then d.waiting[#d.waiting + 1] = n; return end
  show(n)
end
notify.register(receive)

function d.close(n)
  for i, m in ipairs(d.shown) do if m == n or n == nil then table.remove(d.shown, i); break end end
  hypr.relayout = true
end
function d.closeAll() d.shown = {}; hypr.relayout = true end
function d.setPaused(on)
  d.paused = on
  if not on then
    while #d.waiting > 0 and #d.shown < conf.max do show(table.remove(d.waiting, 1)) end
  end
end

print("showing notifications")
local okRun, err = pcall(function()
  while package.loaded["hyprbyte.state"] == hypr do
    local now, gone = computer.uptime(), false
    for i = #d.shown, 1, -1 do
      if d.shown[i].expires and now >= d.shown[i].expires then table.remove(d.shown, i); gone = true end
    end
    if not d.paused then
      while #d.waiting > 0 and #d.shown < conf.max do show(table.remove(d.waiting, 1)) end
    end
    if gone then hypr.relayout = true end
    k.event.pull(0.25)
  end
end)
notify.unregister(receive)
hypr.removeLayer(layer)
package.loaded["dunst.state"] = nil
if not okRun then error(err, 0) end
return 0
