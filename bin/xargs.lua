--[[
  xargs [-n N] [-I STR] [COMMAND ARGS...] - run COMMAND with the words
  of the input as more arguments (default command: echo)

    -n N     at most N words per run of COMMAND
    -I STR   one run per input line, with STR in the arguments replaced
             by that line

    find /tmp -name '*.log' | xargs rm
    ls /etc | xargs -I F echo /etc/F
  Exit status 123 if a run of COMMAND failed.
]]--
local args = arg or {}
local per, place, cmd = nil, nil, {}
local i = 1
while i <= #args do
  local a = args[i]
  if #cmd == 0 and a == "-n" then i = i + 1; per = tonumber(args[i])
  elseif #cmd == 0 and a == "-I" then i = i + 1; place = args[i]
  else cmd[#cmd + 1] = a end
  i = i + 1
end
if #cmd == 0 then cmd = { "echo" } end
if per and per < 1 then term.write("xargs: -n needs a number above 0\n"); return 1 end

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function runWith(list)
  local words = {}
  for _, w in ipairs(list) do words[#words + 1] = quote(w) end
  -- the command prints where xargs prints and does not read the keyboard
  return shell.withIO({ input = "", output = stdio.output }, shell.execute, table.concat(words, " "))
end

local text = stdin.read("a") or ""
local rc = 0
if place then
  for line in text:gmatch("[^\r\n]+") do
    local list = {}
    for n, w in ipairs(cmd) do
      list[n] = w:gsub(place:gsub("%p", "%%%0"), (line:gsub("%%", "%%%%")))
    end
    if runWith(list) ~= 0 then rc = 123 end
    if shell.interrupted then return 130 end
  end
  return rc
end

local items = {}
for w in text:gmatch("%S+") do items[#items + 1] = w end
local n = per or math.max(#items, 1)
for start = 1, math.max(#items, 1), n do
  local list = { table.unpack(cmd) }
  for j = start, math.min(start + n - 1, #items) do list[#list + 1] = items[j] end
  if #items > 0 or start == 1 then
    if runWith(list) ~= 0 then rc = 123 end
  end
  if shell.interrupted then return 130 end
end
return rc
