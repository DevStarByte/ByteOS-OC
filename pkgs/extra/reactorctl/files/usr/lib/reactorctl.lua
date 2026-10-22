--[[
  /usr/lib/reactorctl.lua - Big Reactors / Extreme Reactors through
  OpenComputers, shared by reactorctl and reactorctld

    rc.devices()            -> { reactors = { dev... }, turbines = { dev... } }
                               dev = { addr, proxy }, numbered by address
    rc.reactor(dev)         -> what a reactor reports (missing values nil)
    rc.turbine(dev)         -> what a turbine reports
    rc.config()             -> the settings in /etc/reactorctl.conf
    rc.decide(fill, active, rods, cfg) -> active, rods
                               the automatic rule for one reactor
    rc.step(cfg, report)    -> applies the rule to every reactor once,
                               report(text) for each change

  Every method is called through pcall: the mods' versions differ in what
  they offer (getEnergyCapacity only exists in newer Extreme Reactors).
]]--
local rc = {}
rc.CONF = "/etc/reactorctl.conf"
rc.DEFAULT_CAPACITY = 10000000 -- RF a passive reactor holds (Big Reactors)

-- p.name(...) or nil when the method is missing or fails
local function call(p, name, ...)
  local f = p[name]
  if not f then return nil end
  local ok, v = pcall(f, ...)
  if ok then return v end
end
rc.call = call

function rc.devices()
  local out = { reactors = {}, turbines = {} }
  for addr, kind in component.list() do
    local list = (kind == "br_reactor" and out.reactors) or (kind == "br_turbine" and out.turbines)
    if list then list[#list + 1] = { addr = addr, proxy = component.proxy(addr) } end
  end
  local function byAddr(a, b) return a.addr < b.addr end
  table.sort(out.reactors, byAddr); table.sort(out.turbines, byAddr)
  return out
end

function rc.reactor(dev)
  local p = dev.proxy
  local rods = call(p, "getNumberOfControlRods")
  return {
    connected = call(p, "getConnected") ~= false,
    active = call(p, "getActive") == true,
    energy = call(p, "getEnergyStored"),
    capacity = call(p, "getEnergyCapacity") or rc.DEFAULT_CAPACITY,
    produced = call(p, "getEnergyProducedLastTick"),
    fuel = call(p, "getFuelAmount"), fuelMax = call(p, "getFuelAmountMax"),
    waste = call(p, "getWasteAmount"), burn = call(p, "getFuelConsumedLastTick"),
    fuelTemp = call(p, "getFuelTemperature"), casingTemp = call(p, "getCasingTemperature"),
    rods = rods, rodLevel = rods and rods > 0 and call(p, "getControlRodLevel", 0) or nil,
    cooled = call(p, "isActivelyCooled") == true,
    steam = call(p, "getHotFluidProducedLastTick"),
  }
end

function rc.turbine(dev)
  local p = dev.proxy
  return {
    connected = call(p, "getConnected") ~= false,
    active = call(p, "getActive") == true,
    rpm = call(p, "getRotorSpeed"), energy = call(p, "getEnergyStored"),
    capacity = call(p, "getEnergyCapacity"),
    produced = call(p, "getEnergyProducedLastTick"),
    inductor = call(p, "getInductorEngaged"),
    flowMax = call(p, "getFluidFlowRateMax"),
  }
end

local DEFAULTS = { off_above = 95, on_below = 20, smoothing = 0.5, interval = 5 }

-- "key = value" lines; # starts a comment. Unknown keys and bad values
-- are left out, so the defaults hold.
function rc.config()
  local cfg = {}
  for key, v in pairs(DEFAULTS) do cfg[key] = v end
  local text = kernel.fs.exists(rc.CONF) and kernel.fs.readAll(rc.CONF) or ""
  for line in text:gmatch("[^\r\n]+") do
    local key, v = line:gsub("#.*$", ""):match("^%s*([%w_]+)%s*=%s*([%d%.]+)%s*$")
    if key and DEFAULTS[key] and tonumber(v) then cfg[key] = tonumber(v) end
  end
  cfg.smoothing = math.max(0.05, math.min(1, cfg.smoothing))
  cfg.interval = math.max(0.1, cfg.interval)
  return cfg
end

-- The rule: control rods go in as far (in %) as the energy buffer is full,
-- moving `smoothing` of the way there each step; the reactor stops above
-- off_above % and starts again below on_below %.
function rc.decide(fill, active, rods, cfg)
  local pct = math.max(0, math.min(100, fill * 100))
  local newRods = math.floor((rods or 0) + (pct - (rods or 0)) * cfg.smoothing + 0.5)
  newRods = math.max(0, math.min(100, newRods))
  local newActive = active
  if pct >= cfg.off_above then newActive = false
  elseif pct <= cfg.on_below then newActive = true end
  return newActive, newRods
end

function rc.step(cfg, report)
  for n, dev in ipairs(rc.devices().reactors) do
    local s = rc.reactor(dev)
    -- an actively cooled reactor makes steam, not RF: its buffer says nothing
    if s.connected and not s.cooled and s.energy then
      local fill = s.energy / math.max(1, s.capacity)
      local active, rods = rc.decide(fill, s.active, s.rodLevel, cfg)
      local pct = math.floor(fill * 100 + 0.5)
      if rods ~= s.rodLevel and s.rods and s.rods > 0 then
        call(dev.proxy, "setAllControlRodLevels", rods)
        report(("reactor %d: control rods %d%% -> %d%% (buffer %d%%)"):format(n, s.rodLevel or 0, rods, pct))
      end
      if active ~= s.active then
        call(dev.proxy, "setActive", active)
        report(("reactor %d: %s (buffer %d%%)"):format(n, active and "started" or "stopped", pct))
      end
    end
  end
end

return rc
