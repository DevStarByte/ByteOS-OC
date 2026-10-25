--[[
  /usr/lib/memonitor.lua - an Applied Energistics 2 network through
  OpenComputers, shared by me-monitor and me-monitord

    mm.find()           -> proxy, kind | nil   (an ME controller, else an
                           ME interface, connected by cable or adapter)
    mm.items(p)         -> { { label, name, size }... } summed by label,
                           most first
    mm.power(p)         -> { stored, max, usage, injection } (AE, AE/t)
    mm.cpus(p)          -> { { name, busy, storage }... }
    mm.config()         -> { minimums = { { what, count }... }, interval }
    mm.low(items, cfg)  -> { { what, have, want }... } below their minimum

  Every method is called through pcall: what the integration offers
  differs between versions.
]]--
local mm = {}
mm.CONF = "/etc/me-monitor.conf"

local function call(p, name, ...)
  local f = p[name]
  if not f then return nil end
  local ok, v = pcall(f, ...)
  if ok then return v end
end

function mm.find()
  local found, kind
  for addr, k_ in component.list() do
    if k_ == "me_controller" and kind ~= "me_controller" then found, kind = addr, k_
    elseif k_ == "me_interface" and not found then found, kind = addr, k_ end
  end
  if found then return component.proxy(found), kind end
end

function mm.items(p)
  local sums, order = {}, {}
  for _, it in ipairs(call(p, "getItemsInNetwork") or {}) do
    local label = it.label or it.name or "?"
    local s = sums[label]
    if not s then
      s = { label = label, name = it.name or "?", size = 0, craftable = false }
      sums[label] = s; order[#order + 1] = s
    end
    s.size = s.size + (tonumber(it.size) or 0)
    s.craftable = s.craftable or it.isCraftable == true
  end
  table.sort(order, function(a, b)
    if a.size ~= b.size then return a.size > b.size end
    return a.label < b.label
  end)
  return order
end

function mm.power(p)
  return { stored = call(p, "getStoredPower"), max = call(p, "getMaxStoredPower"),
           usage = call(p, "getAvgPowerUsage"), injection = call(p, "getAvgPowerInjection") }
end

function mm.cpus(p)
  local out = {}
  for i, c in ipairs(call(p, "getCraftingCPUs") or {}) do
    out[#out + 1] = { name = (c.name and c.name ~= "") and c.name or ("CPU " .. i), busy = c.busy == true,
                      storage = c.storage, coprocessors = c.coprocessors }
  end
  return out
end

-- minimum LABEL COUNT   (LABEL may have spaces; with a : it is the item's
--                        name, as minecraft:iron_ingot)
-- interval = SECONDS    how often me-monitord checks (default 60)
function mm.config()
  local cfg = { minimums = {}, interval = 60 }
  local text = kernel.fs.exists(mm.CONF) and kernel.fs.readAll(mm.CONF) or ""
  for raw in text:gmatch("[^\r\n]+") do
    local line = raw:gsub("^%s*#.*$", "")
    local what, count = line:match("^%s*minimum%s+(.-)%s+(%d+)%s*$")
    if what then cfg.minimums[#cfg.minimums + 1] = { what = what, count = tonumber(count) } end
    local iv = line:match("^%s*interval%s*=%s*(%d+%.?%d*)%s*$")
    if iv then cfg.interval = math.max(1, tonumber(iv)) end
  end
  return cfg
end

function mm.low(items, cfg)
  local out = {}
  for _, m in ipairs(cfg.minimums) do
    local have, byName, want = 0, m.what:find(":", 1, true), m.what:lower()
    for _, it in ipairs(items) do
      if (byName and it.name:lower() == want) or (not byName and it.label:lower() == want) then
        have = have + it.size
      end
    end
    if have < m.count then out[#out + 1] = { what = m.what, have = have, want = m.count } end
  end
  return out
end

return mm
