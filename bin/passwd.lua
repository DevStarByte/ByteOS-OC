--[[
  passwd [user] - change a password

  Without a user it changes your own and asks for the current one first.
  root may set anyone's password without knowing the old one.
]]--
local args = arg or {}
local T = term.theme
local me = k.user()
local name = args[1] or me

local function fail(msg)
  term.cwrite(T.err, "passwd: ")
  term.cwrite(T.fg, msg .. "\n")
  return 1
end

if name ~= me and me ~= "root" then return fail("you may not view or modify password information for " .. name) end
if not require("auth").user(fs, name) then return fail("user '" .. name .. "' does not exist") end

local function ask(prompt)
  term.write(prompt)
  local s = term.read({ mask = "•" })
  if s == nil then term.write("\n") end
  return s
end

local old
if me ~= "root" then
  term.write("Changing password for " .. name .. ".\n")
  old = ask("Current password: ")
  if old == nil then return 1 end
end
local new = ask("New password: ")
if new == nil then return 1 end
if new == "" then return fail("the password may not be empty") end
if ask("Retype new password: ") ~= new then return fail("Sorry, passwords do not match.") end

local ok, err = k.changePassword(name, old, new)
if not ok then return fail(err) end
term.write("passwd: password updated successfully\n")
return 0
