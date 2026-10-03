-- /lib/units.lua - human-readable sizes: units.bytes(1536) -> "1.5K"
local units = {}

function units.bytes(n)
  n = tonumber(n) or 0
  if n == math.huge then return "inf" end
  for _, u in ipairs({ "B", "K", "M", "G" }) do
    if n < 1024 or u == "G" then
      if u == "B" then return ("%d%s"):format(n, u) end
      return (n < 10 and "%.1f%s" or "%.0f%s"):format(n, u)
    end
    n = n / 1024
  end
end

return units
