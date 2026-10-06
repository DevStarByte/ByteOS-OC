--[[
  diff [-q] [-U N] FILE1 FILE2 - show how two files differ, line by line

    -q     only say whether they differ
    -U N   N lines of context around each change (default 3)

  The output is in unified format: lines starting with - are only in FILE1,
  + only in FILE2, and @@ -start,count +start,count @@ heads each part.
  Either file may be - for the input. Exit status 0 if the files are the
  same, 1 if they differ, 2 on trouble.

    diff /etc/pacman.conf /etc/pacman.conf.new
]]--
local args = arg or {}
local T = term.theme
local brief, ctx, names = false, 3, {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-q" then brief = true
  elseif a == "-u" then -- unified is the only format
  elseif a == "-U" then i = i + 1; ctx = tonumber(args[i]) or ctx
  else names[#names + 1] = a end
  i = i + 1
end
if #names ~= 2 then term.write("usage: diff [-q] [-U N] FILE1 FILE2\n"); return 2 end

local function lines(name)
  local text, err
  if name == "-" then text = stdin.read("a") or "" else text, err = fs.readAll(shell.normalize(name)) end
  if not text then return nil, err end
  local list = {}
  if text ~= "" and text:sub(-1) ~= "\n" then text = text .. "\n" end
  for l in text:gmatch("([^\n]*)\n") do list[#list + 1] = l end
  return list
end
local a, ea = lines(names[1])
if not a then term.write("diff: " .. names[1] .. ": " .. tostring(ea or "no such file") .. "\n"); return 2 end
local b, eb = lines(names[2])
if not b then term.write("diff: " .. names[2] .. ": " .. tostring(eb or "no such file") .. "\n"); return 2 end

-- The same lines at the start and the end need no search.
local pre = 0
while pre < #a and pre < #b and a[pre + 1] == b[pre + 1] do pre = pre + 1 end
local suf = 0
while suf < #a - pre and suf < #b - pre and a[#a - suf] == b[#b - suf] do suf = suf + 1 end
if pre == #a and pre == #b then return 0 end
if brief then term.write("Files " .. names[1] .. " and " .. names[2] .. " differ\n"); return 1 end

-- Myers' algorithm on the middle part: the shortest list of deletions and
-- insertions. Memory grows with the square of the number of changes, so
-- past MAXD it just replaces the whole middle (still a correct diff).
local MAXD = 120
local function middle()
  local n, m = #a - pre - suf, #b - pre - suf
  local function A(x) return a[pre + x] end
  local function B(y) return b[pre + y] end
  local v, trace = { [1] = 0 }, {}
  for d = 0, math.min(n + m, MAXD) do
    local copy = {}
    for k = -d - 1, d + 1 do copy[k] = v[k] end
    trace[d] = copy
    for k = -d, d, 2 do
      local x
      if k == -d or (k ~= d and v[k - 1] < v[k + 1]) then x = v[k + 1] else x = v[k - 1] + 1 end
      local y = x - k
      while x < n and y < m and A(x + 1) == B(y + 1) do x, y = x + 1, y + 1 end
      v[k] = x
      if x >= n and y >= m then
        -- walk back through the trace, collecting the edits in reverse
        local ops = {}
        for dd = d, 0, -1 do
          local vv, kk = trace[dd], x - y
          local pk
          if kk == -dd or (kk ~= dd and vv[kk - 1] < vv[kk + 1]) then pk = kk + 1 else pk = kk - 1 end
          local px = vv[pk]
          local py = px - pk
          while x > px and y > py do ops[#ops + 1] = { " ", A(x) }; x, y = x - 1, y - 1 end
          if dd > 0 then
            if x == px then ops[#ops + 1] = { "+", B(y) } else ops[#ops + 1] = { "-", A(x) } end
          end
          x, y = px, py
        end
        local fwd = {}
        for j = #ops, 1, -1 do fwd[#fwd + 1] = ops[j] end
        return fwd
      end
    end
  end
  local ops = {}
  for x = 1, n do ops[#ops + 1] = { "-", A(x) } end
  for y = 1, m do ops[#ops + 1] = { "+", B(y) } end
  return ops
end

-- every line of both files as { op, text, lineInA, lineInB }
local ops = {}
for x = 1, pre do ops[#ops + 1] = { " ", a[x] } end
for _, o in ipairs(middle()) do ops[#ops + 1] = o end
for x = #a - suf + 1, #a do ops[#ops + 1] = { " ", a[x] } end
local ai, bi = 0, 0
for _, o in ipairs(ops) do
  o[3], o[4] = ai, bi
  if o[1] ~= "+" then ai = ai + 1 end
  if o[1] ~= "-" then bi = bi + 1 end
end

term.cwrite(T.bright, "--- " .. names[1] .. "\n+++ " .. names[2] .. "\n")
local COLOR = { [" "] = T.fg, ["-"] = T.red, ["+"] = T.green }
local idx = 1
while idx <= #ops do
  if ops[idx][1] == " " then
    idx = idx + 1
  else
    -- a part: changes closer than 2*ctx lines together, with ctx around them
    local first, lastChange, j = math.max(1, idx - ctx), idx, idx + 1
    while j <= #ops do
      if ops[j][1] ~= " " then lastChange = j elseif j - lastChange > 2 * ctx then break end
      j = j + 1
    end
    local stop = math.min(#ops, lastChange + ctx)
    local la, lb = 0, 0
    for k = first, stop do
      if ops[k][1] ~= "+" then la = la + 1 end
      if ops[k][1] ~= "-" then lb = lb + 1 end
    end
    local sa = la > 0 and ops[first][3] + 1 or ops[first][3]
    local sb = lb > 0 and ops[first][4] + 1 or ops[first][4]
    term.cwrite(T.cyan, ("@@ -%d,%d +%d,%d @@\n"):format(sa, la, sb, lb))
    for k = first, stop do term.cwrite(COLOR[ops[k][1]], ops[k][1] .. ops[k][2] .. "\n") end
    idx = stop + 1
  end
end
return 1
