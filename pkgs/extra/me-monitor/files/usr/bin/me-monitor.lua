--[[
  me-monitor - an Applied Energistics 2 network at a glance

    me-monitor              power, items, crafting CPUs, the 10 most items
    me-monitor find TEXT    the items whose name contains TEXT
    me-monitor watch        the overview full screen, every 2 seconds
                            (q quits)
    me-monitor check        the items below their minimum (status 1 if any)

  The computer reaches the network through an ME controller or an ME
  interface, connected by cable or next to an adapter.

  Minimums are set in /etc/me-monitor.conf, one per line:

    minimum Iron Ingot 256           by the name shown in game
    minimum minecraft:redstone 1000  or by the item's id

  The me-monitor service (me-monitord) checks them every minute, writes
  to the system log when an item runs low and again when it is back, and
  shows a notification when a notification daemon (dunst) runs:

    sudo systemctl enable --now me-monitor
]]--
local args = arg or {}
local T = term.theme
local mm = require("memonitor")
package.loaded.memonitor = nil -- needed only while this runs

local function num(n)
  if not n then return "?" end
  local s = ("%d"):format(math.floor(n + 0.5))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(-?),", "%1"))
end

local p = mm.find()
if not p then term.write("me-monitor: no ME controller or ME interface found\n"); return 1 end

local function itemRow(it)
  term.cwrite(T.bright, ("%12s  "):format(num(it.size)))
  term.cwrite(T.fg, it.label)
  term.cwrite(T.muted, "  " .. it.name .. (it.craftable and "  (craftable)" or "") .. "\n")
end

local function overview()
  local pw, items, cpus = mm.power(p), mm.items(p), mm.cpus(p)
  term.cwrite(T.accent, "Power   ")
  local full = (pw.stored and pw.max and pw.max > 0) and math.floor(100 * pw.stored / pw.max + 0.5) or nil
  term.write(("%s / %s AE%s, using %s AE/t, getting %s AE/t\n"):format(num(pw.stored), num(pw.max),
    full and (" (" .. full .. "%)") or "", num(pw.usage), num(pw.injection)))
  local total = 0
  for _, it in ipairs(items) do total = total + it.size end
  term.cwrite(T.accent, "Items   ")
  term.write(("%s kinds, %s in all\n"):format(num(#items), num(total)))
  local busy, names = 0, {}
  for _, c in ipairs(cpus) do
    if c.busy then busy = busy + 1; names[#names + 1] = c.name end
  end
  term.cwrite(T.accent, "CPUs    ")
  term.write(("%d busy, %d idle%s\n"):format(busy, #cpus - busy, #names > 0 and (" (" .. table.concat(names, ", ") .. ")") or ""))
  local lows = mm.low(items, mm.config())
  for _, l in ipairs(lows) do
    term.cwrite(T.yellow, ("low     %s: %s of %s\n"):format(l.what, num(l.have), num(l.want)))
  end
  if #items > 0 then
    term.cwrite(T.accent, "\nMost items\n")
    for i = 1, math.min(10, #items) do itemRow(items[i]) end
  end
end

local cmd = args[1]
if not cmd then overview(); return 0 end
if cmd == "find" then
  local text = table.concat(args, " ", 2):lower()
  if text == "" then term.write("usage: me-monitor find TEXT\n"); return 2 end
  local n = 0
  for _, it in ipairs(mm.items(p)) do
    if it.label:lower():find(text, 1, true) or it.name:lower():find(text, 1, true) then itemRow(it); n = n + 1 end
  end
  if n == 0 then term.write("nothing matches '" .. text .. "'\n"); return 1 end
  return 0
elseif cmd == "check" then
  local cfg = mm.config()
  if #cfg.minimums == 0 then term.write("no minimums in " .. mm.CONF .. "\n"); return 0 end
  local lows = mm.low(mm.items(p), cfg)
  for _, l in ipairs(lows) do term.cwrite(T.yellow, ("low: %s: %s of %s\n"):format(l.what, num(l.have), num(l.want))) end
  if #lows == 0 then term.write(("all %d items are above their minimum\n"):format(#cfg.minimums)); return 0 end
  return 1
elseif cmd == "watch" then
  while true do
    term.clear()
    overview()
    term.cwrite(T.muted, "\nq quits\n")
    local deadline = computer.uptime() + 2
    while computer.uptime() < deadline do
      local ev, _, ch = k.event.pull(deadline - computer.uptime())
      if ev == "key_down" and (ch == 113 or ch == 81) then return 0 end
    end
  end
end
term.write("usage: me-monitor [find TEXT | watch | check]\n")
return 2
