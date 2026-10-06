--[[
  sed [-n] [-i] [-e SCRIPT]... [SCRIPT] [FILE...] - edit lines as they pass

    -n          print only what p asks for
    -i          change the files themselves instead of printing
    -e SCRIPT   one more script (several may be given)

  A script is commands separated by ; or new lines, each with an optional
  address in front: N (line N), $ (the last line), /PATTERN/, or a range
  A,B of them. ! after the address picks the other lines.
    s/PAT/REPL/[g][p][N]  replace PAT (the first, all with g, the N-th)
                          by REPL: & is the whole match, \1..\9 its parts
    d     delete the line          p   print the line
    q     print it and stop        =   print the line number

  Patterns are Lua patterns as in grep: . %d %a %s * + - ? ^ $ (captures
  with ( ) for \1). Any character may stand in for / after s.

    sed s/foo/bar/g notes.txt       sed -n '2,4p' file
    sed -i '/^#/d' /etc/motd        echo a-b | sed 's/(%a)-(%a)/\2-\1/'
]]--
local args = arg or {}
local quiet, inPlace, scripts, files = false, false, {}, {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-n" then quiet = true
  elseif a == "-i" then inPlace = true
  elseif a == "-ni" or a == "-in" then quiet, inPlace = true, true
  elseif a == "-e" then i = i + 1; scripts[#scripts + 1] = args[i] or ""
  elseif a == "-E" or a == "-r" then -- extended regexps: patterns are Lua patterns anyway
  else files[#files + 1] = a end
  i = i + 1
end
-- without -e the first word is the script
if #scripts == 0 and #files > 0 then scripts[1] = table.remove(files, 1) end
if #scripts == 0 then term.write("usage: sed [-n] [-i] [-e SCRIPT]... [SCRIPT] [FILE...]\n"); return 1 end
if inPlace and #files == 0 then term.write("sed: -i needs a file\n"); return 1 end

-- ---- Parsing ---------------------------------------------------------------
local function fail(msg) error({ sed = msg }, 0) end

local function parse(src)
  local cmds, pos = {}, 1
  local function peek() return src:sub(pos, pos) end
  local function skip(set) while pos <= #src and src:sub(pos, pos):match(set) do pos = pos + 1 end end
  -- text up to the next unescaped d; \d stands for d itself
  local function upTo(d)
    local out = {}
    while pos <= #src do
      local c = src:sub(pos, pos)
      if c == "\\" and src:sub(pos + 1, pos + 1) == d then out[#out + 1] = d; pos = pos + 2
      elseif c == "\\" then out[#out + 1] = src:sub(pos, pos + 1); pos = pos + 2
      elseif c == d then pos = pos + 1; return table.concat(out)
      else out[#out + 1] = c; pos = pos + 1 end
    end
    fail("unterminated '" .. d .. "'")
  end
  local function address()
    local n = src:match("^%d+", pos)
    if n then pos = pos + #n; return { line = tonumber(n) } end
    if peek() == "$" then pos = pos + 1; return { last = true } end
    if peek() == "/" then pos = pos + 1; return { pat = upTo("/") } end
  end
  while true do
    skip("[%s;]")
    if pos > #src then break end
    local cmd = { from = address() }
    if cmd.from and peek() == "," then
      pos = pos + 1
      cmd.to = address() or fail("missing address after ,")
    end
    skip("%s")
    if peek() == "!" then cmd.negate = true; pos = pos + 1; skip("%s") end
    local c = peek()
    pos = pos + 1
    if c == "s" then
      local d = peek()
      if d == "" or d:match("[%s\\]") then fail("s needs a delimiter") end
      pos = pos + 1
      cmd.pat, cmd.rep = upTo(d), upTo(d)
      local flags = src:match("^[gp%d]*", pos)
      pos = pos + #flags
      cmd.global, cmd.print = flags:find("g") ~= nil, flags:find("p") ~= nil
      cmd.nth = tonumber(flags:match("%d+"))
      local ok, err = pcall(string.find, "", cmd.pat)
      if not ok then fail("bad pattern: " .. tostring(err)) end
    elseif c == "d" or c == "p" or c == "q" or c == "=" then
      -- nothing more to read
    else
      fail("unknown command '" .. c .. "'")
    end
    cmd.op = c
    cmds[#cmds + 1] = cmd
  end
  return cmds
end

local cmds = {}
for _, s in ipairs(scripts) do
  local ok, list = pcall(parse, s)
  if not ok then term.write("sed: " .. (type(list) == "table" and list.sed or tostring(list)) .. "\n"); return 1 end
  for _, c in ipairs(list) do cmds[#cmds + 1] = c end
end

-- ---- Running ---------------------------------------------------------------
-- s///: the pattern wrapped so the whole match is the first capture
-- (^ and $ have to stay outside to remain anchors)
local function wrapped(pat)
  local head = pat:sub(1, 1) == "^" and "^" or ""
  local body = pat:sub(#head + 1)
  local tail = ""
  if body:sub(-1) == "$" and body:sub(-2, -2) ~= "%" then body, tail = body:sub(1, -2), "$" end
  return head .. "(" .. body .. ")" .. tail
end
for _, c in ipairs(cmds) do if c.op == "s" then c.wrapped = wrapped(c.pat) end end

-- REPL with & and \1.. filled in from caps (caps[1] is the whole match)
local function replacement(rep, caps)
  local out, i = {}, 1
  while i <= #rep do
    local c = rep:sub(i, i)
    if c == "\\" and i < #rep then
      local d = rep:sub(i + 1, i + 1)
      if d:match("%d") then out[#out + 1] = tostring(caps[tonumber(d) + 1] or "")
      elseif d == "n" then out[#out + 1] = "\n"
      elseif d == "t" then out[#out + 1] = "\t"
      else out[#out + 1] = d end
      i = i + 2
    else
      out[#out + 1] = c == "&" and caps[1] or c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function substitute(c, line)
  local count, done = 0, false
  local out = line:gsub(c.wrapped, function(...)
    count = count + 1
    if (c.nth and count ~= c.nth) or (not c.nth and not c.global and count > 1) then return nil end
    done = true
    return replacement(c.rep, { ... })
  end)
  return out, done
end

local function matches(addr, line, n, isLast)
  if addr.line then return n == addr.line end
  if addr.last then return isLast end
  return line:find(addr.pat) ~= nil
end

local function selected(c, line, n, isLast)
  if not c.from then return true end
  local hit
  if not c.to then
    hit = matches(c.from, line, n, isLast)
  elseif c.active then
    hit = true
    if (c.to.line and n >= c.to.line) or (not c.to.line and matches(c.to, line, n, isLast)) then c.active = false end
  elseif matches(c.from, line, n, isLast) then
    hit = true
    -- a line number at or before this line ends the range at once
    c.active = not (c.to.line and c.to.line <= n)
  end
  if c.negate then hit = not hit end
  return hit
end

-- Runs the script over text; returns the output and whether q stopped it.
local function edit(text)
  if text ~= "" and text:sub(-1) ~= "\n" then text = text .. "\n" end
  local lines = {}
  for l in text:gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
  local out = {}
  for _, c in ipairs(cmds) do c.active = false end
  for n, line in ipairs(lines) do
    local isLast, deleted, stop = n == #lines, false, false
    for _, c in ipairs(cmds) do
      if selected(c, line, n, isLast) then
        if c.op == "s" then
          local changed
          line, changed = substitute(c, line)
          if changed and c.print then out[#out + 1] = line end
        elseif c.op == "d" then deleted = true; break
        elseif c.op == "p" then out[#out + 1] = line
        elseif c.op == "=" then out[#out + 1] = tostring(n)
        elseif c.op == "q" then stop = true; break
        end
      end
    end
    if not deleted and not quiet then out[#out + 1] = line end
    if stop then break end
  end
  return #out > 0 and (table.concat(out, "\n") .. "\n") or ""
end

if #files == 0 then
  term.write(edit(stdin.read("a") or ""))
  return 0
end
local rc = 0
for _, f in ipairs(files) do
  local path = shell.normalize(f)
  local text, err = fs.readAll(path)
  if not text then
    term.write("sed: " .. f .. ": " .. tostring(err or "no such file") .. "\n"); rc = 1
  elseif inPlace then
    local ok, werr = fs.writeAll(path, edit(text))
    if not ok then term.write("sed: " .. f .. ": " .. tostring(werr) .. "\n"); rc = 1 end
  else
    term.write(edit(text))
  end
end
return rc
