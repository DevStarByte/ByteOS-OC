--[[
  id [-u|-g|-G] [-n] [user] - print user and group ids

    id              uid=1000(alice) gid=100(users) groups=100(users),10(wheel)
    id -u / -g      only the user id / the primary group's id
    id -G           every group id, separated by spaces
    -n              names instead of numbers:  id -un  prints alice
]]--
local auth = require("auth")
local which, names, name = nil, false, nil
for _, a in ipairs(arg or {}) do
  if a:sub(1, 1) == "-" and #a > 1 then
    for f in a:sub(2):gmatch(".") do
      if f == "u" or f == "g" or f == "G" then which = f
      elseif f == "n" then names = true
      else term.write("id: unknown option -" .. f .. "\n"); return 2 end
    end
  else
    name = a
  end
end
if names and not which then term.write("id: -n needs -u, -g or -G\n"); return 2 end
name = name or k.user()
local u = auth.user(fs, name)
if not u then term.write("id: '" .. name .. "': no such user\n"); return 1 end
local list = auth.groupsOf(fs, name)
local primary = { gid = u.gid, name = tostring(u.gid) }
for _, g in ipairs(list) do
  if g.gid == u.gid then primary = g end
end

if which == "u" then
  term.write((names and u.name or tostring(u.uid)) .. "\n")
elseif which == "g" then
  term.write((names and primary.name or tostring(primary.gid)) .. "\n")
elseif which == "G" then
  local out = { names and primary.name or tostring(primary.gid) }
  for _, g in ipairs(list) do
    if g.gid ~= u.gid then out[#out + 1] = names and g.name or tostring(g.gid) end
  end
  term.write(table.concat(out, " ") .. "\n")
else
  local groups = {}
  for _, g in ipairs(list) do groups[#groups + 1] = ("%d(%s)"):format(g.gid, g.name) end
  local p = primary.name ~= tostring(primary.gid) and ("%d(%s)"):format(primary.gid, primary.name) or tostring(primary.gid)
  term.write(("uid=%d(%s) gid=%s groups=%s\n"):format(u.uid, u.name, p, table.concat(groups, ",")))
end
return 0
