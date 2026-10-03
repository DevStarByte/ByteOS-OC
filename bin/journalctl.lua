--[[
  journalctl [-n N] [-u name] [-f] - show the system log (/var/log/messages)

    -n N      only the last N lines
    -u name   only lines from that service or program (sudo, login, pacman...)
    -f        keep showing new lines as they arrive (Ctrl+C ends it)
]]--
local args = arg or {}
local n, unit, follow
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-n" then i = i + 1; n = tonumber(args[i])
  elseif a == "-u" or a == "-t" then i = i + 1; unit = args[i]
  elseif a == "-f" then follow = true
  else term.write("usage: journalctl [-n N] [-u name] [-f]\n"); return 1 end
  i = i + 1
end
local LOG = "/var/log/messages"

local function matching(text)
  local out = {}
  for line in text:gmatch("[^\n]+") do
    if not unit or line:find(" " .. unit .. ": ", 1, true) then out[#out + 1] = line end
  end
  return out
end

local text = fs.readAll(LOG) or ""
local lines = matching(text)
for j = (n and math.max(1, #lines - n + 1) or 1), #lines do term.write(lines[j] .. "\n") end
if not follow then return 0 end
local seen = #text
while true do
  k.event.pull(1)
  local now = fs.readAll(LOG) or ""
  if #now < seen then seen = 0 end -- the log was shortened
  for _, l in ipairs(matching(now:sub(seen + 1))) do term.write(l .. "\n") end
  seen = #now
end
