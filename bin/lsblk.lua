-- lsblk - the disks in this computer and where they are mounted
local units = require("units")
local T = term.theme
local where = {}
for _, m in ipairs(k.fs.mounts()) do where[m.proxy.address] = m.path end
term.cwrite(T.bright, ("%-9s %-6s %-12s %6s %6s %-3s %s\n"):format("NAME", "TYPE", "LABEL", "SIZE", "USED", "RO", "MOUNTPOINT"))
local rows = {}
for addr in component.list("filesystem") do
  local p = component.proxy(addr)
  local tmp = computer.tmpAddress and computer.tmpAddress() == addr
  rows[#rows + 1] = { addr:sub(1, 8), tmp and "tmpfs" or "fs", (p.getLabel and p.getLabel()) or "",
    units.bytes(p.spaceTotal()), units.bytes(p.spaceUsed()), p.isReadOnly() and "yes" or "no", where[addr] or "" }
end
for addr in component.list("drive") do
  local p = component.proxy(addr)
  rows[#rows + 1] = { addr:sub(1, 8), "drive", (p.getLabel and p.getLabel()) or "",
    units.bytes(p.getCapacity()), "-", "no", "(unmanaged)" }
end
table.sort(rows, function(a, b) return a[7] < b[7] end)
for _, r in ipairs(rows) do
  term.write(("%-9s %-6s %-12s %6s %6s %-3s %s\n"):format(r[1], r[2], term.usub(r[3], 1, 12), r[4], r[5], r[6], r[7]))
end
return 0
