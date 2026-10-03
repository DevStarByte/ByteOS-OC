--[[
  userdel [-r] name - delete a user (root only)

    -r   also remove the home directory
]]--
local auth = require("auth")
local args = arg or {}
local T = term.theme

local function fail(msg)
  term.cwrite(T.err, "userdel: ")
  term.cwrite(T.fg, msg .. "\n")
  return 1
end
if k.user() ~= "root" then return fail("Permission denied.") end

local removeHome, name = false, nil
for _, a in ipairs(args) do
  if a == "-r" then removeHome = true
  elseif a:sub(1, 1) == "-" then return fail("unknown option " .. a)
  else name = a end
end
if not name then term.write("usage: userdel [-r] name\n"); return 1 end
local u = auth.user(fs, name)
if not u then return fail("user '" .. name .. "' does not exist") end
if name == "root" then return fail("the root account cannot be deleted") end
if name == _G.USER then return fail("user " .. name .. " is currently logged in") end

auth.delUser(fs, name)
if removeHome and u.home ~= "/" and fs.exists(u.home) then fs.remove(u.home) end
return 0
