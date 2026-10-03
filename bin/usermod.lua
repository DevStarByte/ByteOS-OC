--[[
  usermod -aG group,... name   add a user to groups (root only)
  usermod -rG group,... name   remove a user from groups

  e.g. `usermod -aG wheel alice` lets alice use sudo.
]]--
local auth = require("auth")
local args = arg or {}
local T = term.theme

local function fail(msg)
  term.cwrite(T.err, "usermod: ")
  term.cwrite(T.fg, msg .. "\n")
  return 1
end
if k.user() ~= "root" then return fail("Permission denied.") end

local mode, list, name = args[1], args[2], args[3]
if (mode ~= "-aG" and mode ~= "-rG") or not list or not name then
  term.write("usage: usermod -aG|-rG group,... name\n")
  return 1
end
if not auth.user(fs, name) then return fail("user '" .. name .. "' does not exist") end
for g in list:gmatch("[^,]+") do
  local ok, e
  if mode == "-aG" then ok, e = auth.addToGroup(fs, name, g)
  else ok, e = auth.removeFromGroup(fs, name, g) end
  if not ok then return fail(e or ("cannot change group " .. g)) end
end
return 0
