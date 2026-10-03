--[[
  hyprpaper - a wallpaper behind Hyprbyte's windows

  Shows on empty workspaces and in the gaps between windows: a text
  picture in the middle and a pattern around it. Reads
  ~/.config/hypr/hyprpaper.conf (else /etc/hypr/hyprpaper.conf) and
  follows changes to it. Start it with Hyprbyte: exec-once = hyprpaper.
  Pictures: /usr/share/hyprpaper/ (byteos.txt, mountains.txt, cat.txt).
]]--
local T = term.theme
local hypr = package.loaded["hyprbyte.state"]
if not hypr or not hypr.grab then print("hyprpaper: Hyprbyte 1.2 or newer is not running"); return 1 end
local own = (_G.HOME or "/") .. "/.config/hypr/hyprpaper.conf"
local function path() return fs.exists(own) and own or "/etc/hypr/hyprpaper.conf" end

local PATTERNS = {
  dots = function(x, y) return (x % 6 == 0 and y % 3 == 0) and "·" end,
  grid = function(x, y) if y % 4 == 0 then return x % 8 == 0 and "┼" or "─" end return x % 8 == 0 and "│" end,
  stars = function(x, y) local n = (x * 7919 + y * 104729) % 97; return n == 0 and "*" or n == 1 and "." or n == 2 and "+" end,
  waves = function(x, y) return y % 3 == 0 and ((x + y) % 8 < 4 and "~" or "∽") end,
}

local conf, source, art = {}, nil, {}
local function load()
  source = fs.readAll(path()) or ""
  conf = { pattern = "dots", color = "accent", pattern_color = "raised" }
  for line in source:gmatch("[^\r\n]+") do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key then conf[key] = value end
  end
  art = {}
  if conf.wallpaper and conf.wallpaper ~= "none" then
    for l in (fs.readAll(conf.wallpaper) or ""):gmatch("([^\n]*)\n?") do art[#art + 1] = l end
    while art[#art] == "" do art[#art] = nil end
  end
end
load()

local layer = {
  namespace = "hyprpaper", anchor = "background",
  draw = function(gpu, x, y, w, h)
    local pat = PATTERNS[conf.pattern]
    if pat then
      gpu.setForeground(T[conf.pattern_color] or T.raised)
      for yy = 0, h - 1 do
        local row, any = {}, false
        for xx = 0, w - 1 do
          local c = pat(xx, yy)
          row[#row + 1] = c or " "
          any = any or c ~= nil
        end
        if any then gpu.set(x, y + yy, table.concat(row)) end
      end
    end
    if #art > 0 then
      local aw = 0
      for _, l in ipairs(art) do aw = math.max(aw, term.ulen(l)) end
      local ax, ay = x + math.max(0, (w - aw) // 2), y + math.max(0, (h - #art) // 2)
      gpu.setForeground(T[conf.color] or T.accent)
      for i, l in ipairs(art) do
        -- spaces in the picture stay see-through: draw only its runs of characters
        local col = 1
        for pre, run in l:gmatch("( *)([^ ]+)") do
          col = col + term.ulen(pre)
          gpu.set(ax + col - 1, ay + i - 1, run)
          col = col + term.ulen(run)
        end
      end
    end
  end,
}
hypr.addLayer(layer)
print("wallpaper: " .. tostring(conf.wallpaper) .. ", pattern: " .. tostring(conf.pattern))
local nextCheck = computer.uptime() + 2
while package.loaded["hyprbyte.state"] == hypr do
  if computer.uptime() >= nextCheck then
    nextCheck = computer.uptime() + 2
    if (fs.readAll(path()) or "") ~= source then load(); hypr.relayout = true end
  end
  k.event.pull(1)
end
return 0
