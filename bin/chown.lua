--[[
  chown [-R] OWNER[:GROUP] FILE... - give files to another user (root only)

    alice         the owner becomes alice
    alice:wheel   owner alice, group wheel
    :wheel        only the group
    -R            also everything inside directories

    sudo chown -R alice /home/shared
]]--
local auth = require("auth")
local args = arg or {}
local recursive, spec, files = false, nil, {}
for _, a in ipairs(args) do
  if a == "-R" then recursive = true
  elseif not spec then spec = a
  else files[#files + 1] = a end
end
if not spec or #files == 0 then term.write("usage: chown [-R] OWNER[:GROUP] FILE...\n"); return 1 end

local owner, group = spec:match("^([^:]*):?(.*)$")
if owner == "" then owner = nil end
if group == "" then group = nil end
if not owner and not group then term.write("chown: say whom to give the files to\n"); return 1 end
if owner and not auth.user(fs, owner) then term.write("chown: no such user: " .. owner .. "\n"); return 1 end
if group then
  local known = false
  for _, g in ipairs(auth.groups(fs)) do if g.name == group then known = true end end
  if not known then term.write("chown: no such group: " .. group .. "\n"); return 1 end
end

local rc = 0
local function change(path, shown)
  local ok, err = fs.chown(path, owner, group)
  if not ok then term.write("chown: " .. shown .. ": " .. tostring(err) .. "\n"); rc = 1; return end
  if recursive and fs.isDirectory(path) then
    for _, e in ipairs(fs.list(path) or {}) do
      local name = e:gsub("/$", "")
      change(path .. "/" .. name, shown .. "/" .. name)
    end
  end
end
-- PERMS is written once, after all the files
fs.permsBatch(function()
  for _, f in ipairs(files) do change(shell.normalize(f), f) end
end)
return rc
