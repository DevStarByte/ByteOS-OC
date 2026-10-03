--[[
  hyprlock - lock Hyprbyte's screen

  Hides every window behind a big clock until you type your password and
  press Enter (Mod+L in Hyprbyte; hypridle can do it after a while without
  input). Nothing you type reaches the windows meanwhile. A wrong password
  makes it wait a little longer each time.
]]--
local T = term.theme
local hypr = package.loaded["hyprbyte.state"]
if not hypr or not hypr.grab then print("hyprlock: Hyprbyte 1.2 or newer is not running"); return 1 end
for _, l in ipairs(hypr.layers) do if l.namespace == "hyprlock" then return 0 end end

local user = k.user()
local input, message, fails, waitUntil, done = "", nil, 0, 0, false

local FONT = {
  ["0"] = { "███", "█ █", "█ █", "█ █", "███" }, ["1"] = { " █ ", "██ ", " █ ", " █ ", "███" },
  ["2"] = { "███", "  █", "███", "█  ", "███" }, ["3"] = { "███", "  █", "███", "  █", "███" },
  ["4"] = { "█ █", "█ █", "███", "  █", "  █" }, ["5"] = { "███", "█  ", "███", "  █", "███" },
  ["6"] = { "███", "█  ", "███", "█ █", "███" }, ["7"] = { "███", "  █", "  █", "  █", "  █" },
  ["8"] = { "███", "█ █", "███", "█ █", "███" }, ["9"] = { "███", "█ █", "███", "  █", "███" },
  [":"] = { " ", "█", " ", "█", " " },
}
-- "12:34" in big letters, each pixel two columns wide: five strings
local function big(text)
  local rows = { "", "", "", "", "" }
  for c in text:gmatch(".") do
    local g = FONT[c] or FONT[":"]
    for r = 1, 5 do
      rows[r] = rows[r] .. g[r]:gsub(utf8.charpattern, function(p) return p .. p end) .. "  "
    end
  end
  return rows
end
local function centre(gpu, x, w, y, text)
  gpu.set(x + math.max(0, (w - term.ulen(text)) // 2), y, text)
end

local layer
layer = {
  namespace = "hyprlock", anchor = "overlay", exclusive = true,
  draw = function(gpu, x, y, w, h)
    gpu.setBackground(T.base); gpu.fill(x, y, w, h, " ")
    local okC, clock = pcall(require, "clock")
    local now = okC and clock.date("%H:%M") or os.date("%H:%M")
    local top = y + math.max(1, h // 2 - 6)
    gpu.setForeground(T.accent)
    for r, line in ipairs(big(now)) do centre(gpu, x, w, top + r - 1, line) end
    gpu.setForeground(T.muted)
    centre(gpu, x, w, top + 6, okC and clock.date("%A, %d %B") or "")
    gpu.setForeground(T.fg)
    centre(gpu, x, w, top + 8, "Locked · " .. user)
    local field = string.rep("•", term.ulen(input))
    local fw = 24
    local fx = x + (w - fw) // 2
    gpu.setBackground(T.raised); gpu.fill(fx, top + 10, fw, 1, " ")
    gpu.setForeground(T.bright)
    gpu.set(fx + 1, top + 10, input == "" and "" or term.usub(field, -(fw - 2)))
    if input == "" then gpu.setForeground(T.dim); gpu.set(fx + 1, top + 10, "password") end
    gpu.setBackground(T.base)
    if message then gpu.setForeground(T.red); centre(gpu, x, w, top + 12, message) end
    gpu.setBackground(T.bg)
  end,
  key = function(ev, _, ch, code)
    if ev ~= "key_down" then return end
    if computer.uptime() < waitUntil then message = "wait a moment…"; return end
    if code == 28 or code == 156 then
      if k.checkPassword(user, input) then
        done = true
        hypr.removeLayer(layer)
        return
      end
      fails = fails + 1
      input = ""
      message = "wrong password"
      waitUntil = computer.uptime() + math.min(30, fails * 2)
      k.log("hyprlock: wrong password for " .. user, "auth")
    elseif code == 14 then input = term.usub(input, 1, -2)
    elseif code == 1 then input = ""
    elseif ch and ch >= 32 and ch ~= 127 then
      input = input .. (unicode and unicode.char or utf8.char)(math.floor(ch)); message = nil
    end
  end,
}
hypr.addLayer(layer)
hypr.grab(layer)
while not done and package.loaded["hyprbyte.state"] == hypr do k.event.pull(0.5) end
return 0
