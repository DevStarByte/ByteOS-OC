-- ls - list directory contents
--   -a  show hidden (dot) files     -l  long listing     -1  one per line
local T = term.theme
local args = arg or {}
local opts, paths = {}, {}
for _, a in ipairs(args) do
  if a:sub(1, 1) == "-" and #a > 1 then
    for f in a:sub(2):gmatch(".") do opts[f] = true end
  else
    paths[#paths + 1] = a
  end
end
if #paths == 0 then paths[1] = _G.PWD or "/" end

local function colorFor(name, isDir)
  if isDir then return T.blue end
  if name:sub(1, 1) == "." then return T.muted end
  if name:match("%.lua$") then return T.green end
  if name:match("%.pkg$") or name:match("%.pkg%.z$") or name:match("%.db$") then return T.magenta end
  return T.fg
end

local function human(n)
  if n < 1024 then return tostring(n) end
  if n < 1024 * 1024 then return ("%.1fK"):format(n / 1024) end
  return ("%.1fM"):format(n / 1048576)
end

local function listing(path)
  local entries = {}
  for _, e in ipairs(k.fs.list(path)) do
    local name = e:gsub("/$", "")
    if opts.a or name:sub(1, 1) ~= "." then
      local full = (path == "/" and "" or path) .. "/" .. name
      local isDir = k.fs.isDirectory(full)
      entries[#entries + 1] = { name = name, dir = isDir, full = full }
    end
  end
  -- directories first, then files, each alphabetical
  table.sort(entries, function(a, b)
    if a.dir ~= b.dir then return a.dir end
    return a.name:lower() < b.name:lower()
  end)
  return entries
end

local function long(entries)
  for _, e in ipairs(entries) do
    local size = e.dir and "-" or human(k.fs.size(e.full) or 0)
    term.cwrite(T.muted, (e.dir and "d" or "-") .. (e.name:match("%.lua$") and "rwxr-xr-x" or "rw-r--r--") .. "  ")
    term.cwrite(T.fg, ("%6s  "):format(size))
    term.cwrite(colorFor(e.name, e.dir), e.name .. (e.dir and "/" or ""))
    term.write("\n")
  end
end

-- Column-major grid, like GNU ls: fill each column top to bottom.
local function grid(entries)
  if #entries == 0 then return end
  local W = term.size()
  local maxlen = 0
  for _, e in ipairs(entries) do maxlen = math.max(maxlen, term.ulen(e.name)) end
  local colw = maxlen + 2
  local cols = opts["1"] and 1 or math.max(1, math.floor((W + 1) / colw))
  local rows = math.ceil(#entries / cols)
  cols = math.ceil(#entries / rows)
  for r = 1, rows do
    for c = 1, cols do
      local e = entries[(c - 1) * rows + r]
      if e then
        local last = c == cols or not entries[c * rows + r]
        term.cwrite(colorFor(e.name, e.dir), last and e.name or term.pad(e.name, colw))
      end
    end
    term.write("\n")
  end
end

local rc = 0
for i, p in ipairs(paths) do
  local path = shell.normalize(p)
  if not k.fs.exists(path) then
    shell.err("ls", "cannot access '" .. p .. "': no such file or directory")
    rc = 2
  elseif not k.fs.isDirectory(path) then
    if opts.l then long({ { name = p, dir = false, full = path } })
    else term.cwrite(colorFor(p, false), p .. "\n") end
  else
    if #paths > 1 then
      if i > 1 then term.write("\n") end
      term.cwrite(T.bright, p .. ":\n")
    end
    local entries = listing(path)
    if opts.l then long(entries) else grid(entries) end
  end
end
return rc
