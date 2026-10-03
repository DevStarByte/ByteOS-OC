--[[
  useradd [-m] [-G group,...] [-s shell] name - create a user (root only)

    -m   create the home directory /home/<name> with a copy of /etc/skel
    -G   supplementary groups, e.g. -G wheel to allow sudo
    -s   login shell (default /bin/sh)

  The new account is locked until you give it a password: passwd <name>
]]--
local auth = require("auth")
local args = arg or {}
local T = term.theme

local function fail(msg)
  term.cwrite(T.err, "useradd: ")
  term.cwrite(T.fg, msg .. "\n")
  return 1
end
if k.user() ~= "root" then return fail("Permission denied.") end

local makeHome, groups, sh, name = false, {}, nil, nil
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-m" then makeHome = true
  elseif a == "-G" then
    i = i + 1
    for g in (args[i] or ""):gmatch("[^,]+") do groups[#groups + 1] = g end
  elseif a == "-s" then i = i + 1; sh = args[i]
  elseif a:sub(1, 1) == "-" then return fail("unknown option " .. a)
  else name = a end
  i = i + 1
end
if not name then
  term.write("usage: useradd [-m] [-G group,...] [-s shell] name\n")
  return 1
end
if not auth.validName(name) then return fail("invalid user name '" .. name .. "'") end
if auth.user(fs, name) then return fail("user '" .. name .. "' already exists") end
local known = {}
for _, g in ipairs(auth.groups(fs)) do known[g.name] = true end
for _, g in ipairs(groups) do
  if not known[g] then return fail("group '" .. g .. "' does not exist") end
end

auth.addUser(fs, name, { groups = groups, shell = sh })
if makeHome then
  local home = "/home/" .. name
  if not fs.exists(home) then fs.makeDirectory(home) end
  for _, f in ipairs(fs.list("/etc/skel") or {}) do
    if not f:match("/$") then fs.writeAll(home .. "/" .. f, fs.readAll("/etc/skel/" .. f)) end
  end
end
term.cwrite(T.muted, "user '" .. name .. "' created; give it a password with ")
term.cwrite(T.blue, "passwd " .. name .. "\n")
return 0
