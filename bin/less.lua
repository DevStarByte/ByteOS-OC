--[[
  less [file] - read text one screen at a time (a file or its input)

    ↓ j Enter  next line          ↑ k        previous line
    Space PgDn next page          b PgUp     previous page
    g Home     start              G End      end
    /text      search             n          next match
    q          quit
]]--
local args = arg or {}
local T = term.theme
local text, title
if args[1] and args[1] ~= "-" then
  local err
  text, err = fs.readAll(shell.normalize(args[1]))
  if not text then term.write("less: " .. args[1] .. ": " .. tostring(err or "no such file") .. "\n"); return 1 end
  title = args[1]
else
  text, title = stdin.read("a") or "", "(input)"
end
if stdio and stdio.output then term.write(text); return 0 end -- into a pipe: just pass it on

local W, H = term.size()
local rows = H - 1
-- split into screen lines, wrapping long ones
local lines = {}
for raw in (text:gsub("\n$", "") .. "\n"):gmatch("([^\n]*)\n") do
  local line = raw:gsub("\r$", ""):gsub("\t", "    ")
  if line == "" then lines[#lines + 1] = "" end
  while term.ulen(line) > 0 do
    lines[#lines + 1] = term.usub(line, 1, W)
    line = term.usub(line, W + 1)
  end
end
local top, query = 1, nil
local maxTop = math.max(1, #lines - rows + 1)

local function draw(note)
  term.clear()
  for r = 1, rows do
    local l = lines[top + r - 1]
    if not l then break end
    term.setCursor(1, r)
    term.write(l)
  end
  term.setCursor(1, H)
  local pct = #lines == 0 and 100 or math.floor(100 * math.min(#lines, top + rows - 1) / #lines)
  term.cwrite(T.muted, note or ((top >= maxTop and "(END) " or ": ") .. title .. ("  %d%%"):format(pct)))
end

local function search(from)
  if not query or query == "" then return "no search" end
  local q = query:lower()
  for i = from, #lines do
    if lines[i]:lower():find(q, 1, true) then top = math.min(i, maxTop); return nil end
  end
  return "pattern not found: " .. query
end

local note
while true do
  draw(note)
  note = nil
  local key = term.readKey()
  if key == "q" or key == "Q" or key == "ctrl+c" then break
  elseif key == "down" or key == "j" or key == "enter" then top = math.min(maxTop, top + 1)
  elseif key == "up" or key == "k" then top = math.max(1, top - 1)
  elseif key == " " or key == "pagedown" or key == "f" then top = math.min(maxTop, top + rows)
  elseif key == "b" or key == "pageup" then top = math.max(1, top - rows)
  elseif key == "g" or key == "home" then top = 1
  elseif key == "G" or key == "end" then top = maxTop
  elseif key == "/" then
    term.setCursor(1, H); term.write(string.rep(" ", W - 1)); term.setCursor(1, H); term.write("/")
    query = term.read()
    note = search(top + 1)
  elseif key == "n" then note = search(top + 1)
  end
end
term.clear()
return 0
