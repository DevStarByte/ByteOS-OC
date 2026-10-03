--[[
  btop [-1] - watch the whole system on one screen

  Memory and energy with their history, the disks, the network card,
  the services and every process, updated every second.

    Up/Down     pick a process
    k           stop the picked process (yours, or any as root)
    q           quit (Ctrl+C too)

    -1          draw the screen once and end (for scripts)
]]--
local T = term.theme
local args = arg or {}
local once = args[1] == "-1"
local okSd, systemd = pcall(require, "systemd")

local SPARK = { " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local HISTORY = 120
local memHist, energyHist = {}, {}
local selected, message = 1, nil
local netSeen, netRate, netCount, netSince = 0, 0, 0, computer.uptime()

local function push(list, v)
  list[#list + 1] = v
  if #list > HISTORY then table.remove(list, 1) end
end

local function at(x, y, color, text)
  term.setCursor(x, y)
  term.cwrite(color, text)
end

local function kib(n) return ("%d KiB"):format(math.floor(n / 1024 + 0.5)) end

local function box(x, y, w, h, title)
  if once then term.cwrite(T.accent, title .. "\n"); return end -- plain text, no frames
  if w < 4 or h < 2 then return end
  at(x, y, T.dim, "┌" .. string.rep("─", w - 2) .. "┐")
  for i = 1, h - 2 do
    at(x, y + i, T.dim, "│"); at(x + w - 1, y + i, T.dim, "│")
  end
  at(x, y + h - 1, T.dim, "└" .. string.rep("─", w - 2) .. "┘")
  at(x + 2, y, T.accent, " " .. title .. " ")
end

local function bar(x, y, w, frac, color)
  local n = math.floor(w * math.max(0, math.min(1, frac)) + 0.5)
  at(x, y, color, string.rep("█", n))
  at(x + n, y, T.raised, string.rep("░", w - n))
end

local function spark(x, y, w, hist, max)
  local parts = {}
  for i = math.max(1, #hist - w + 1), #hist do
    local level = math.floor(8 * hist[i] / math.max(max, 1) + 0.5)
    parts[#parts + 1] = SPARK[math.max(0, math.min(8, level)) + 1]
  end
  at(x, y, T.cyan, string.rep(" ", w - #parts) .. table.concat(parts))
end

local function uptime(s)
  s = math.floor(s)
  return ("%d:%02d:%02d"):format(s // 3600, s % 3600 // 60, s % 60)
end

local function fit(s, w)
  s = tostring(s)
  if term.ulen(s) > w then return term.usub(s, 1, math.max(0, w - 1)) .. "…" end
  return s .. string.rep(" ", w - term.ulen(s))
end

local function draw()
  local W, H = term.size()
  if not once then H = math.min(H, 50) end
  term.clear()
  local total, free = computer.totalMemory(), computer.freeMemory()
  local energy, maxE = computer.energy(), computer.maxEnergy()

  -- header
  local okC, clock = pcall(require, "clock")
  local now = okC and clock.date("%H:%M:%S") or ""
  term.setBackground(T.raised)
  at(1, 1, T.bright, fit(" btop  " .. (_G.HOSTNAME or "byteos") .. "  up " .. uptime(computer.uptime()), W - 10) .. fit(now, 10))
  term.setBackground(T.bg)
  if once then term.write("\n") end

  -- memory and energy, side by side
  local half = W // 2
  box(1, 2, half, 5, "memory")
  local used = total - free
  at(3, 3, T.fg, fit(("%s of %s used (%d%%)"):format(kib(used), kib(total), math.floor(100 * used / total + 0.5)), half - 4))
  bar(3, 4, half - 4, used / total, T.green)
  spark(3, 5, half - 4, memHist, total)
  if once then term.write("\n") end
  box(half + 1, 2, W - half, 5, "energy")
  at(half + 3, 3, T.fg, fit(("%.0f of %.0f (%d%%)"):format(energy, maxE, math.floor(100 * energy / math.max(maxE, 1) + 0.5)), W - half - 4))
  bar(half + 3, 4, W - half - 4, energy / math.max(maxE, 1), T.yellow)
  spark(half + 3, 5, W - half - 4, energyHist, maxE)
  if once then term.write("\n") end

  -- disks | network and services
  local mounts = fs.mounts()
  local services = okSd and systemd.list() or {}
  local rows = math.max(#mounts, 2 + #services, 2)
  rows = math.min(rows, math.max(2, (H - 7) // 2 - 2))
  box(1, 7, half, rows + 2, "disks")
  table.sort(mounts, function(a, b) return a.path < b.path end)
  for i, m in ipairs(mounts) do
    if i > rows then break end
    local p = m.proxy
    local totalD, usedD = 0, 0
    if not p.netfs then -- a shared folder would mean network requests every second
      local okT, t = pcall(p.spaceTotal); local okU, u = pcall(p.spaceUsed)
      totalD, usedD = okT and tonumber(t) or 0, okU and tonumber(u) or 0
    end
    local label = fit(m.path, 12)
    at(3, 7 + i, T.blue, label)
    local bw = math.max(4, half - 34)
    if p.netfs then
      at(16, 7 + i, T.muted, fit(p.netfs.host .. ":" .. p.netfs.share, half - 18))
    elseif totalD > 0 and totalD < math.huge then
      bar(16, 7 + i, bw, usedD / totalD, T.magenta)
      at(17 + bw, 7 + i, T.muted, fit(kib(usedD) .. "/" .. kib(totalD), half - bw - 18))
    else
      at(16, 7 + i, T.muted, "-")
    end
    if once then term.write("\n") end
  end
  box(half + 1, 7, W - half, rows + 2, "network · services")
  local modem = component.list("modem")()
  if modem then
    local card = component.proxy(modem)
    local okW, wireless = pcall(card.isWireless)
    at(half + 3, 8, T.fg, fit(("card %s %s  %d msg/s"):format(modem:sub(1, 8), (okW and wireless) and "wireless" or "wired", netRate), W - half - 4))
  else
    at(half + 3, 8, T.muted, "no network card")
  end
  if once then term.write("\n") end
  for i, name in ipairs(services) do
    if i + 1 > rows then break end
    local st = systemd.status(name).active
    local color = st == "active" and T.green or st == "failed" and T.red or T.muted
    at(half + 3, 8 + i, color, "● ")
    at(half + 5, 8 + i, T.fg, fit(name, 14))
    at(half + 20, 8 + i, color, fit(st, W - half - 22))
    if once then term.write("\n") end
  end

  -- processes
  local top = 7 + rows + 2
  local list = k.process.list()
  if selected > #list then selected = #list end
  if selected < 1 then selected = 1 end
  local ph = math.max(3, H - top)
  box(1, top, W, ph, "processes")
  at(3, top + 1, T.bright, fit(("%5s  %-8s %-9s %8s  %s"):format("PID", "USER", "STATE", "TIME", "NAME"), W - 4))
  if once then term.write("\n") end
  local visible = ph - 3
  local first = math.max(1, math.min(selected - visible + 1, #list - visible + 1))
  for i = first, math.min(#list, first + visible - 1) do
    local p = list[i]
    local line = fit(("%5d  %-8s %-9s %8s  %s"):format(p.pid, fit(p.user, 8), p.state,
      uptime(computer.uptime() - (p.started or 0)), p.name), W - 4)
    local y = top + 2 + i - first
    if i == selected and not once then
      term.setBackground(T.accent); at(3, y, T.bright, line); term.setBackground(T.bg)
    else
      at(3, y, p.user == "root" and T.fg or T.green, line)
    end
    if once then term.write("\n") end
  end
  if not once then
    at(2, H, T.muted, message or "↑↓ pick  k stop  q quit")
  end
  return list
end

local function sample()
  push(memHist, computer.totalMemory() - computer.freeMemory())
  push(energyHist, computer.energy())
  local now = computer.uptime()
  if now - netSince >= 1 then
    netRate, netCount, netSince = netCount / (now - netSince), 0, now
  end
end

sample()
if once then draw(); return 0 end

local list
local okRun, err = pcall(function()
  local nextDraw = 0
  while true do
    if computer.uptime() >= nextDraw then
      sample()
      list = draw()
      nextDraw = computer.uptime() + 1
    end
    local ev, _, ch, code = k.event.pull(math.max(0.05, nextDraw - computer.uptime()))
    if ev == "modem_message" then netCount = netCount + 1 end
    if ev == "key_down" then
      message = nil
      if ch == 113 or ch == 81 then return end
      if code == 200 then selected = selected - 1; nextDraw = 0
      elseif code == 208 then selected = selected + 1; nextDraw = 0
      elseif code == 201 then selected = selected - 10; nextDraw = 0
      elseif code == 209 then selected = selected + 10; nextDraw = 0
      elseif ch == 107 and list and list[selected] then
        local p = list[selected]
        local okK, why = k.process.kill(p.pid)
        message = okK and ("stopped " .. p.pid .. " (" .. p.name .. ")") or ("cannot stop " .. p.pid .. ": " .. tostring(why))
        nextDraw = 0
      end
    end
  end
end)
term.setBackground(T.bg)
term.clear()
if not okRun and not tostring(err):find("interrupted") then error(err, 0) end
return 0
