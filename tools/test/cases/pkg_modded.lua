-- Packages for modded Minecraft: reactorctl (Big/Extreme Reactors) and
-- me-monitor (Applied Energistics 2), against fake components.
users()
local P = dofile(REPO .. "/tools/test/pkgrepo.lua")
if not P then return end
local function idle(sec) kernel.event.pull(sec) end

-- a reactor as Extreme Reactors shows it through its Computer Port
local function fakeReactor(r)
  return {
    getConnected = function() return true end,
    getActive = function() return r.active end, setActive = function(v) r.active = v end,
    getEnergyStored = function() return r.energy end,
    getEnergyCapacity = r.cap and function() return r.cap end or nil,
    getEnergyProducedLastTick = function() return 1234.5 end,
    getFuelAmount = function() return 12000 end, getFuelAmountMax = function() return 20000 end,
    getWasteAmount = function() return 300 end, getFuelConsumedLastTick = function() return 0.052 end,
    getFuelTemperature = function() return 812.4 end, getCasingTemperature = function() return 701 end,
    getNumberOfControlRods = function() return 4 end,
    getControlRodLevel = function(i) return i == 0 and r.rods or nil end,
    setAllControlRodLevels = function(n) r.rods = n end,
    isActivelyCooled = function() return r.cooled == true end,
    getHotFluidProducedLastTick = function() return 500 end,
  }
end

test("reactorctl installs; no reactor is said plainly", function()
  local out = run(P .. "-S reactorctl me-monitor")
  lacks(out, "error")
  local o, rc = run("reactorctl")
  eq(rc, 1); has(o, "no reactor or turbine found")
  ok(file("/etc/reactorctl.conf"), "the settings are installed")
  lacks(file("/etc/systemd/enabled") or "", "reactorctl", "automatic control is off until enabled")
end)

test("reactorctl shows reactors and turbines", function()
  local r = { active = true, energy = 5000000, cap = 10000000, rods = 30 }
  plug("br_reactor", "br000000-1", fakeReactor(r))
  plug("br_turbine", "bt000000-1", {
    getConnected = function() return true end, getActive = function() return true end,
    getRotorSpeed = function() return 1795.6 end, getEnergyStored = function() return 42000 end,
    getEnergyProducedLastTick = function() return 2100 end, getInductorEngaged = function() return true end,
    getFluidFlowRateMax = function() return 2000 end,
  })
  local out, rc = run("reactorctl")
  undisk("br000000-1"); undisk("bt000000-1")
  eq(rc, 0)
  has(out, "Reactor 1  br000000  on")
  has(out, "5,000,000 / 10,000,000 RF (50%)")
  has(out, "1,235 RF/t")
  has(out, "12,000 / 20,000 mB (60%), waste 300 mB, burning 0.052 mB/t")
  has(out, "fuel 812 °C, casing 701 °C")
  has(out, "30% in (4 rods)")
  has(out, "Turbine 1  bt000000  on"); has(out, "1,796 RPM, inductor engaged"); has(out, "at most 2,000 mB/t")
end)

test("reactorctl on, off and rods", function()
  local a = { active = true, energy = 0, cap = 1000, rods = 0 }
  local b = { active = true, energy = 0, rods = 0 }  -- older: no getEnergyCapacity
  plug("br_reactor", "br000000-1", fakeReactor(a))
  plug("br_reactor", "br000000-2", fakeReactor(b))
  local off = run("reactorctl off 2")
  local rods = run("reactorctl rods 70")
  local bad = run("reactorctl rods 170")
  local none = run("reactorctl on 5")
  local status = run("reactorctl")
  undisk("br000000-1"); undisk("br000000-2")
  has(off, "1 reactor stopped"); eq(a.active, true); eq(b.active, false)
  has(rods, "control rods 70% in"); eq(a.rods, 70); eq(b.rods, 70)
  has(bad, "LEVEL 0-100")
  has(none, "no reactor 5")
  has(status, "/ 10,000,000 RF", "a passive reactor without getEnergyCapacity holds 10 million")
end)

test("the automatic rule: rods follow the buffer, off when full, on when low", function()
  put("/etc/reactorctl.conf", "off_above = 90\non_below = 25\nsmoothing = 1\n")
  local r = { active = true, energy = 400, cap = 1000, rods = 0 }
  plug("br_reactor", "br000000-1", fakeReactor(r))
  local steps = {}
  local function at(energy) r.energy = energy; steps[#steps + 1] = run("reactorctl auto") end
  at(400); local rods40 = r.rods
  at(950); local off = r.active
  at(500); local still = r.active
  at(100); local on = r.active
  at(100)
  undisk("br000000-1")
  eq(rods40, 40); has(steps[1], "reactor 1: control rods 0% -> 40% (buffer 40%)")
  eq(off, false); has(steps[2], "reactor 1: stopped (buffer 95%)")
  eq(still, false, "between the thresholds it stays off")
  eq(on, true); has(steps[4], "reactor 1: started (buffer 10%)")
  has(steps[5], "nothing to change")
  -- smoothing moves the rods part of the way each step
  put("/etc/reactorctl.conf", "smoothing = 0.5\n")
  r.rods, r.energy = 0, 800
  plug("br_reactor", "br000000-1", fakeReactor(r))
  run("reactorctl auto"); local first = r.rods
  run("reactorctl auto"); local second = r.rods
  undisk("br000000-1")
  eq(first, 40); eq(second, 60)
end)

test("an actively cooled reactor is left alone", function()
  put("/etc/reactorctl.conf", "smoothing = 1\n")
  local r = { active = true, energy = 0, rods = 10, cooled = true }
  plug("br_reactor", "br000000-1", fakeReactor(r))
  local out = run("reactorctl auto")
  local status = run("reactorctl")
  undisk("br000000-1")
  has(out, "nothing to change"); eq(r.rods, 10); eq(r.active, true)
  has(status, "on, actively cooled"); has(status, "500 mB/t")
end)

test("reactorctld runs the rule as a service and logs it", function()
  put("/etc/reactorctl.conf", "smoothing = 1\ninterval = 0.2\n")
  local r = { active = true, energy = 300, cap = 1000, rods = 0 }
  plug("br_reactor", "br000000-1", fakeReactor(r))
  local out, rc = run("systemctl start reactorctl")
  idle(0.5)
  r.energy = 990
  idle(0.5)
  run("systemctl stop reactorctl")
  undisk("br000000-1")
  eq(rc, 0, out)
  eq(r.active, false); eq(r.rods, 99)
  local log = file("/var/log/messages")
  has(log, "reactorctl: reactorctld started")
  has(log, "reactorctl: reactor 1: control rods 0% -> 30% (buffer 30%)")
  has(log, "reactorctl: reactor 1: stopped (buffer 99%)")
end)

test("reactorctl watch refreshes until q", function()
  local r = { active = false, energy = 10, cap = 1000, rods = 0 }
  plug("br_reactor", "br000000-1", fakeReactor(r))
  signals({ function() end, { "key_down", "kbd", ("q"):byte(), 16 } })
  local out, rc = run("reactorctl watch")
  undisk("br000000-1")
  eq(rc, 0); has(out, "Reactor 1"); has(out, "q quits")
end)

-- an ME network as the AE2 integration shows it
local function fakeME(net)
  return {
    getItemsInNetwork = function()
      local list = {}
      for _, it in ipairs(net.items) do list[#list + 1] = { label = it[1], name = it[2], size = it[3], isCraftable = it[4] } end
      return list
    end,
    getCraftingCPUs = function() return net.cpus end,
    getStoredPower = function() return 1600 end, getMaxStoredPower = function() return 3200 end,
    getAvgPowerUsage = function() return 12.4 end, getAvgPowerInjection = function() return 40 end,
  }
end
local NET = {
  items = {
    { "Iron Ingot", "minecraft:iron_ingot", 200 }, { "Iron Ingot", "minecraft:iron_ingot", 40 },
    { "Cobblestone", "minecraft:cobblestone", 54321 }, { "Redstone", "minecraft:redstone", 900, true },
    { "Gold Ingot", "minecraft:gold_ingot", 12 },
  },
  cpus = { { name = "big", busy = true }, { name = "", busy = false } },
}

test("me-monitor: power, items, CPUs, the most items, find", function()
  local none, nrc = run("me-monitor")
  plug("me_interface", "me000000-1", fakeME(NET))
  local out, rc = run("me-monitor")
  local found = run("me-monitor find ingot")
  local nothing, frc = run("me-monitor find diamond")
  undisk("me000000-1")
  eq(nrc, 1); has(none, "no ME controller or ME interface found")
  eq(rc, 0)
  has(out, "1,600 / 3,200 AE (50%), using 12 AE/t, getting 40 AE/t")
  has(out, "4 kinds, 55,473 in all")
  has(out, "1 busy, 1 idle (big)")
  has(out, "      54,321  Cobblestone")
  local cobble, iron = out:find("Cobblestone", 1, true), out:find("Iron Ingot", 1, true)
  ok(cobble < iron, "most first")
  has(out, "         240  Iron Ingot", "stacks with the same name are added up")
  has(out, "minecraft:redstone  (craftable)")
  has(found, "Iron Ingot"); has(found, "Gold Ingot"); lacks(found, "Cobblestone")
  eq(frc, 1); has(nothing, "nothing matches 'diamond'")
end)

test("me-monitor check and the minimums", function()
  put("/etc/me-monitor.conf", "# keep these\nminimum Iron Ingot 256\nminimum minecraft:redstone 500\nminimum Gold Ingot 10\n")
  plug("me_controller", "me000000-1", fakeME(NET))
  local out, rc = run("me-monitor check")
  local overview = run("me-monitor")
  undisk("me000000-1")
  eq(rc, 1); has(out, "low: Iron Ingot: 240 of 256"); lacks(out, "Redstone"); lacks(out, "Gold")
  has(overview, "low     Iron Ingot: 240 of 256")
  put("/etc/me-monitor.conf", "minimum gold ingot 5\n")
  plug("me_controller", "me000000-1", fakeME(NET))
  local fine, frc = run("me-monitor check")
  undisk("me000000-1")
  eq(frc, 0); has(fine, "all 1 items are above their minimum")
end)

test("me-monitord logs an item running low, and back", function()
  put("/etc/me-monitor.conf", "minimum Gold Ingot 20\ninterval = 1\n")
  local net = { items = { { "Gold Ingot", "minecraft:gold_ingot", 12 } }, cpus = {} }
  plug("me_controller", "me000000-1", fakeME(net))
  local out, rc = run("systemctl start me-monitor")
  idle(0.5)
  idle(1.2)  -- a second check: no second alert while it stays low
  net.items[1][3] = 30
  idle(1.2)
  run("systemctl stop me-monitor")
  undisk("me000000-1")
  eq(rc, 0, out)
  local log = file("/var/log/messages")
  has(log, "me-monitor: me-monitord started: 1 minimums, every 1s")
  has(log, "me-monitor: low on Gold Ingot: 12 of 20")
  local _, alerts = log:gsub("low on Gold Ingot", "")
  eq(alerts, 1, "one alert while it stays low")
  has(log, "me-monitor: Gold Ingot is back above its minimum")
end)

test("man pages for the commands", function()
  has(run("man reactorctl"), "Big Reactors / Extreme Reactors")
  has(run("man me-monitor"), "Applied Energistics 2")
end)
