-- df - disk space of every mounted filesystem
local units = require("units")
local T = term.theme
local list = k.fs.mounts()
table.sort(list, function(a, b) return a.path < b.path end)
term.cwrite(T.bright, ("%-12s %6s %6s %6s %4s  %s\n"):format("Filesystem", "Size", "Used", "Avail", "Use%", "Mounted on"))
for _, m in ipairs(list) do
  local p = m.proxy
  local total = (p.spaceTotal and p.spaceTotal()) or 0
  local used = (p.spaceUsed and p.spaceUsed()) or 0
  local label = (p.getLabel and p.getLabel()) or p.address:sub(1, 8)
  local pct = (total > 0 and total ~= math.huge) and math.floor(100 * used / total + 0.5) or 0
  term.write(("%-12s %6s %6s %6s %3d%%  %s\n"):format(term.usub(label, 1, 12), units.bytes(total),
    units.bytes(used), units.bytes(math.max(0, total - used)), pct, m.path))
end
return 0
