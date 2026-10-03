local path = "/usr/share/fortune/quotes.txt"
if not fs.exists(path) then term.write("fortune: missing data\n"); return 1 end
local quotes = {}
for line in (fs.readAll(path) or ""):gmatch("[^\n]+") do
  if line:match("%S") then quotes[#quotes + 1] = line end
end
if #quotes == 0 then term.write("fortune: empty\n"); return 1 end
math.randomseed(math.floor(_G.computer.uptime() * 1000) % 2147483647)
term.setForeground(0xFFCC55)
term.write("  " .. quotes[math.random(#quotes)] .. "\n")
term.setForeground(0xFFFFFF)
return 0
