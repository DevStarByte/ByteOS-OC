-- du [-s] [-h] [path...] - disk usage of directories (KiB, or -h readable)
--   -s  only the total for each path
local units = require("units")
local args = arg or {}
local opt, paths = {}, {}
for _, a in ipairs(args) do
  if a:match("^%-%a+$") then for f in a:sub(2):gmatch(".") do opt[f] = true end
  else paths[#paths + 1] = a end
end
if #paths == 0 then paths = { "." } end
local function show(size, name)
  term.write((opt.h and units.bytes(size) or tostring(math.ceil(size / 1024))) .. "\t" .. name .. "\n")
end
local function walk(real, display, top)
  if not fs.isDirectory(real) then return fs.size(real) or 0 end
  local sum = 0
  for _, e in ipairs(fs.list(real) or {}) do
    local n = e:gsub("/$", "")
    sum = sum + walk((real == "/" and "" or real) .. "/" .. n, display:gsub("/$", "") .. "/" .. n, false)
  end
  if not opt.s or top then show(sum, display) end
  return sum
end
local rc = 0
for _, p in ipairs(paths) do
  local real = shell.normalize(p)
  if not fs.exists(real) then term.write("du: cannot access '" .. p .. "'\n"); rc = 1
  elseif fs.isDirectory(real) then walk(real, p, true)
  else show(fs.size(real) or 0, p) end
end
return rc
