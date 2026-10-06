--[[
  sha256sum [FILE...]   print the SHA-256 checksum of each file (or of the input)
  sha256sum -c LIST     check the files named in LIST ("<sum>  <file>" lines,
                        as sha256sum prints them): OK or FAILED for each

  Fast with a tier 3 data card, slower without one.
]]--
local sha256 = require("sha256")
local args = arg or {}

local function read(f)
  if f == "-" then return stdin.read("a") or "" end
  return fs.readAll(shell.normalize(f))
end

if args[1] == "-c" then
  local list, err = read(args[2] or "-")
  if not list then term.write("sha256sum: " .. args[2] .. ": " .. tostring(err) .. "\n"); return 1 end
  local bad = 0
  for line in list:gmatch("[^\r\n]+") do
    local sum, name = line:match("^(%x+)%s+%*?(.+)$")
    if sum then
      local data = read(name)
      local good = data and sha256.hex(data) == sum:lower()
      term.write(name .. ": " .. (good and "OK" or "FAILED") .. "\n")
      if not good then bad = bad + 1 end
    end
  end
  if bad > 0 then term.write("sha256sum: " .. bad .. " checksum(s) did NOT match\n"); return 1 end
  return 0
end

local files = #args > 0 and args or { "-" }
local rc = 0
for _, f in ipairs(files) do
  local data, err = read(f)
  if data then term.write(sha256.hex(data) .. "  " .. f .. "\n")
  else term.write("sha256sum: " .. f .. ": " .. tostring(err or "no such file") .. "\n"); rc = 1 end
end
return rc
