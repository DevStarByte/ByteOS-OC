--[[
  find [path...] [-name pattern] [-type f|d] [-maxdepth n] - list files

    -name    file names matching a wildcard pattern: -name '*.lua'
             (quote it, or the shell expands it first)
    -type    f for files, d for directories
    -maxdepth how many directory levels to descend
]]--
local args = arg or {}
local paths, name, kind, maxdepth = {}, nil, nil, math.huge
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-name" then i = i + 1; name = args[i]
  elseif a == "-type" then i = i + 1; kind = args[i]
  elseif a == "-maxdepth" then i = i + 1; maxdepth = tonumber(args[i]) or maxdepth
  elseif a:sub(1, 1) == "-" then term.write("find: unknown option " .. a .. "\n"); return 1
  else paths[#paths + 1] = a end
  i = i + 1
end
if #paths == 0 then paths = { "." } end

local pattern
if name then
  pattern = "^" .. name:gsub("[%^%$%(%)%%%.%+%-]", "%%%0"):gsub("%*", ".*"):gsub("%?", ".") .. "$"
end

local function walk(real, show, depth)
  local isDir = fs.isDirectory(real)
  local base = show:match("([^/]+)/?$") or show
  if (not pattern or base:match(pattern)) and (not kind or (kind == "d") == isDir) then
    term.write(show .. "\n")
  end
  if isDir and depth < maxdepth then
    for _, e in ipairs(fs.list(real) or {}) do
      local n = e:gsub("/$", "")
      walk((real == "/" and "" or real) .. "/" .. n, (show == "/" and "" or show:gsub("/$", "")) .. "/" .. n, depth + 1)
    end
  end
end

local rc = 0
for _, p in ipairs(paths) do
  local real = shell.normalize(p)
  if fs.exists(real) then walk(real, p, 0)
  else term.write("find: '" .. p .. "': no such file or directory\n"); rc = 1 end
end
return rc
