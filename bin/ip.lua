-- ip - this computer's network cards, their addresses and the host name
local T = term.theme
local any = false
for addr in component.list("modem") do
  any = true
  local c = component.proxy(addr)
  term.cwrite(T.bright, "card " .. addr:sub(1, 8) .. "  ")
  term.write((c.isWireless() and "wireless" or "wired") .. "\n")
  term.write("    address " .. addr .. "\n")
  if c.isWireless() and c.getStrength then term.write("    range   " .. c.getStrength() .. " blocks\n") end
  term.write("    ByteNet port 4400 " .. (c.isOpen(4400) and "open (netd)" or "closed") .. "\n")
end
term.write("hostname " .. tostring(_G.HOSTNAME) .. "\n")
if not any then term.write("no network card\n"); return 1 end
return 0
