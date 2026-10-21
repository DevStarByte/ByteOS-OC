--[[
  watch [-n SECS] [-t] COMMAND... - run a command again and again, full screen

    watch free                 memory, every 2 seconds
    watch -n 1 'ps | wc -l'    every second; quote pipes and ;
    -t                         no title line

  q or Ctrl+C ends it. Output longer or wider than the screen is cut off.
]]--
local args = arg or {}
local T = term.theme
local secs, title = 2, true
local i = 1
while args[i] and args[i]:sub(1, 1) == "-" do
  local a = args[i]
  if a == "-n" or a == "--interval" then
    i = i + 1
    secs = tonumber(args[i] or "")
    if not secs then shell.err("watch", "-n needs a number of seconds"); return 1 end
  elseif a:match("^%-n%d") then secs = tonumber(a:sub(3))
  elseif a == "-t" or a == "--no-title" then title = false
  elseif a == "--" then i = i + 1; break
  else shell.err("watch", "unknown option " .. a); return 1 end
  i = i + 1
end
if not args[i] then term.write("usage: watch [-n SECS] [-t] COMMAND...\n"); return 1 end
secs = math.max(0.1, secs or 2)

-- One argument is taken as a whole command line (watch 'ps | wc -l');
-- several are quoted so they reach the command as they are.
local line
if not args[i + 1] then
  line = args[i]
else
  local words = {}
  for j = i, #args do
    local w = args[j]
    words[#words + 1] = w:match("^[%w%-_./=:,+@%%]+$") and w or ("'" .. w:gsub("'", "'\\''") .. "'")
  end
  line = table.concat(words, " ")
end

local clock = require("clock")
local function frame()
  local errs = {}
  local prevSink = shell.errorSink()
  shell.setErrorSink(function(t) errs[#errs + 1] = t end)
  local ok, text = pcall(shell.capture, line)
  shell.setErrorSink(prevSink)
  if not ok then errs[#errs + 1] = tostring(text) .. "\n"; text = "" end
  text = text .. (text ~= "" and #errs > 0 and "\n" or "") .. table.concat(errs)
  local W, H = term.size()
  term.clear()
  term.setCursor(1, 1)
  local rows = H - 1
  if title then
    local right = clock.date("%a %b %e %H:%M:%S")
    local left = term.usub(("Every %.1fs: %s"):format(secs, line), 1, math.max(1, W - term.ulen(right) - 2))
    term.cwrite(T.accent, left)
    term.write(string.rep(" ", math.max(1, W - term.ulen(left) - term.ulen(right))))
    term.cwrite(T.muted, right .. "\n\n")
    rows = rows - 2
  end
  local n = 0
  for l in (text:gsub("\n+$", "") .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    if n > rows then break end
    term.write(term.usub(l, 1, W) .. "\n")
  end
end

local ev = k.event
while true do
  frame()
  local deadline = computer.uptime() + secs
  local ok, quit = pcall(function()
    while true do
      local left = deadline - computer.uptime()
      if left <= 0 then return false end
      local name, _, ch = ev.pull(left)
      if name == "key_down" and (ch == 113 or ch == 81) then return true end
    end
  end)
  if not ok then
    if quit ~= "interrupted" then error(quit, 0) end
    break
  end
  if quit then break end
end
return 0
