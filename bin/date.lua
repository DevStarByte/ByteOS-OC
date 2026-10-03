-- date [+FORMAT] - the current date and time (OpenComputers' clock)
--   date +%H:%M     any os.date format after the +
local fmt = (arg or {})[1]
if fmt and fmt:sub(1, 1) ~= "+" then term.write("usage: date [+FORMAT]\n"); return 1 end
local ok, s = pcall(os.date, fmt and fmt:sub(2) or "%a %b %d %H:%M:%S %Y")
if not ok then term.write("date: " .. tostring(s) .. "\n"); return 1 end
term.write(tostring(s) .. "\n")
return 0
