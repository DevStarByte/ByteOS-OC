--[[
  lshw [-short] [class] - every component in this computer

  Shows what OpenComputers reports about each device: its class, product,
  vendor, capacity, clock and so on. A class (processor, memory, display,
  network, volume, ...) shows only those devices.

    -short   one line per device
]]--
local T = term.theme
local args = arg or {}
local short, only = false, nil
for _, a in ipairs(args) do
  if a == "-short" or a == "-s" then short = true else only = a end
end

local devices = {}
local info = (computer.getDeviceInfo and computer.getDeviceInfo()) or {}
for addr, d in pairs(info) do devices[addr] = d end
-- components OpenComputers gave no details for still get a line
for addr, kind in component.list() do
  devices[addr] = devices[addr] or { class = kind, description = kind }
end

local list = {}
for addr, d in pairs(devices) do
  if not only or d.class == only then list[#list + 1] = { addr = addr, d = d } end
end
table.sort(list, function(a, b)
  if a.d.class ~= b.d.class then return tostring(a.d.class) < tostring(b.d.class) end
  return a.addr < b.addr
end)
if #list == 0 then term.write("lshw: no " .. (only or "devices") .. " found\n"); return 1 end

if short then
  term.cwrite(T.bright, ("%-10s %-12s %s\n"):format("ADDRESS", "CLASS", "DESCRIPTION"))
  for _, e in ipairs(list) do
    term.write(("%-10s %-12s %s\n"):format(e.addr:sub(1, 8), tostring(e.d.class),
      tostring(e.d.product or e.d.description or "")))
  end
  return 0
end

local ORDER = { "description", "product", "vendor", "version", "capacity", "size", "width", "clock", "serial" }
for _, e in ipairs(list) do
  term.cwrite(T.accent, "*-" .. tostring(e.d.class))
  term.cwrite(T.muted, "  " .. e.addr .. "\n")
  local shown = {}
  for _, key in ipairs(ORDER) do
    if e.d[key] then
      term.cwrite(T.bright, ("     %-13s"):format(key .. ":"))
      term.write(tostring(e.d[key]) .. "\n")
      shown[key] = true
    end
  end
  for key, v in pairs(e.d) do
    if not shown[key] and key ~= "class" then
      term.cwrite(T.bright, ("     %-13s"):format(key .. ":"))
      term.write(tostring(v) .. "\n")
    end
  end
end
return 0
