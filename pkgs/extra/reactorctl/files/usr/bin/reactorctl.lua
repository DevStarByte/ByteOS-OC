--[[
  reactorctl - Big Reactors / Extreme Reactors: status and control

    reactorctl                      every reactor and turbine
    reactorctl watch                the same, full screen, every second
                                    (q quits)
    reactorctl on|off [N]           start or stop reactor N (all of them)
    reactorctl on|off turbine [N]   the same for turbines
    reactorctl rods LEVEL [N]       control rods LEVEL % in (0 = full power)
    reactorctl auto                 apply the automatic rule once, now

  The reactors and turbines are found through their Computer Port,
  connected to the computer by cable. Reactors and turbines are numbered
  in the order of their addresses.

  Automatic control is the reactorctl service (reactorctld): every few
  seconds it puts the control rods in as far as the energy buffer is full
  (50 % full: rods 50 % in), stops a reactor above 95 % and starts it
  again below 20 %. Changes go to the system log. Settings are in
  /etc/reactorctl.conf:

    sudo systemctl enable --now reactorctl
    journalctl -u reactorctl
]]--
local args = arg or {}
local T = term.theme
local rc = require("reactorctl")
package.loaded.reactorctl = nil -- needed only while this runs

local function num(n)
  if not n then return "?" end
  local s = ("%d"):format(math.floor(n + 0.5))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(-?),", "%1"))
end
local function pct(a, b) return (a and b and b > 0) and math.floor(100 * a / b + 0.5) or nil end
local function bar(frac, width)
  local n = math.floor(width * math.max(0, math.min(1, frac or 0)) + 0.5)
  return string.rep("█", n) .. string.rep("░", width - n)
end
local function line(label, text, colour)
  term.cwrite(T.bright, term.pad(label, 10))
  term.cwrite(colour or T.fg, text .. "\n")
end

local function show(devs)
  local W = term.size()
  for n, dev in ipairs(devs.reactors) do
    local s = rc.reactor(dev)
    term.cwrite(T.accent, ("Reactor %d"):format(n))
    term.cwrite(T.muted, "  " .. dev.addr:sub(1, 8) .. "  ")
    if not s.connected then term.cwrite(T.red, "not assembled\n")
    else
      term.cwrite(s.active and T.green or T.yellow, (s.active and "on" or "off") .. (s.cooled and ", actively cooled" or "") .. "\n")
      if s.cooled then
        line("  Steam", num(s.steam) .. " mB/t")
      else
        local p = pct(s.energy, s.capacity)
        line("  Energy", ("%s / %s RF (%s%%)"):format(num(s.energy), num(s.capacity), p or "?"))
        term.cwrite(T.green, "          " .. bar((p or 0) / 100, math.max(10, math.min(40, W - 12))) .. "\n")
        line("  Output", num(s.produced) .. " RF/t")
      end
      line("  Fuel", ("%s / %s mB (%s%%), waste %s mB, burning %.3f mB/t"):format(num(s.fuel), num(s.fuelMax),
        pct(s.fuel, s.fuelMax) or "?", num(s.waste), s.burn or 0))
      line("  Heat", ("fuel %s °C, casing %s °C"):format(num(s.fuelTemp), num(s.casingTemp)))
      if s.rods then line("  Rods", ("%s%% in (%d rods)"):format(s.rodLevel or "?", s.rods)) end
    end
  end
  for n, dev in ipairs(devs.turbines) do
    local s = rc.turbine(dev)
    term.cwrite(T.accent, ("Turbine %d"):format(n))
    term.cwrite(T.muted, "  " .. dev.addr:sub(1, 8) .. "  ")
    if not s.connected then term.cwrite(T.red, "not assembled\n")
    else
      term.cwrite(s.active and T.green or T.yellow, (s.active and "on" or "off") .. "\n")
      line("  Rotor", num(s.rpm) .. " RPM, inductor " .. (s.inductor and "engaged" or "disengaged"))
      line("  Output", num(s.produced) .. " RF/t")
      line("  Energy", num(s.energy) .. " RF" .. (s.capacity and (" / " .. num(s.capacity) .. " RF") or ""))
      if s.flowMax then line("  Steam", "at most " .. num(s.flowMax) .. " mB/t") end
    end
  end
end

local devs = rc.devices()
if #devs.reactors + #devs.turbines == 0 then
  term.write("reactorctl: no reactor or turbine found (connect its Computer Port by cable)\n")
  return 1
end

-- the devices a command means: kind "reactor"/"turbine", number N or all
local function pick(kind, n)
  local list = kind == "turbine" and devs.turbines or devs.reactors
  if not n then return list end
  if not list[n] then return nil end
  return { list[n] }
end

local cmd = args[1]
if not cmd then show(devs); return 0 end

if cmd == "on" or cmd == "off" then
  local kind, n = "reactor", nil
  local i = 2
  if args[i] == "turbine" or args[i] == "reactor" then kind = args[i]; i = i + 1 end
  if args[i] then n = tonumber(args[i]) if not n then term.write("reactorctl: not a number: " .. args[i] .. "\n"); return 2 end end
  local list = pick(kind, n)
  if not list or #list == 0 then term.write(("reactorctl: no %s %s\n"):format(kind, n or "")); return 1 end
  for _, dev in ipairs(list) do rc.call(dev.proxy, "setActive", cmd == "on") end
  term.write(("%d %s%s %s\n"):format(#list, kind, #list == 1 and "" or "s", cmd == "on" and "started" or "stopped"))
  return 0
elseif cmd == "rods" then
  local level = tonumber(args[2])
  if not level or level < 0 or level > 100 then term.write("usage: reactorctl rods LEVEL [N]   (LEVEL 0-100)\n"); return 2 end
  local list = pick("reactor", tonumber(args[3]))
  if not list or #list == 0 then term.write("reactorctl: no reactor " .. (args[3] or "") .. "\n"); return 1 end
  for _, dev in ipairs(list) do rc.call(dev.proxy, "setAllControlRodLevels", math.floor(level)) end
  term.write(("control rods %d%% in\n"):format(math.floor(level)))
  return 0
elseif cmd == "auto" then
  local changed = false
  rc.step(rc.config(), function(text) term.write(text .. "\n"); changed = true end)
  if not changed then term.write("nothing to change\n") end
  return 0
elseif cmd == "watch" then
  while true do
    term.clear()
    show(rc.devices())
    term.cwrite(T.muted, "q quits\n")
    local deadline = computer.uptime() + 1
    while computer.uptime() < deadline do
      local ev, _, ch = k.event.pull(deadline - computer.uptime())
      if ev == "key_down" and (ch == 113 or ch == 81) then return 0 end
    end
  end
end
term.write("usage: reactorctl [watch | on|off [turbine] [N] | rods LEVEL [N] | auto]\n")
return 2
