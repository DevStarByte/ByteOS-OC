-- id [user] - print user and group ids:  uid=1000(alice) gid=100(users) groups=...
local auth = require("auth")
local name = (arg or {})[1] or k.user()
local u = auth.user(fs, name)
if not u then term.write("id: '" .. name .. "': no such user\n"); return 1 end
local primary, groups = tostring(u.gid), {}
for _, g in ipairs(auth.groupsOf(fs, name)) do
  if g.gid == u.gid then primary = ("%d(%s)"):format(g.gid, g.name) end
  groups[#groups + 1] = ("%d(%s)"):format(g.gid, g.name)
end
term.write(("uid=%d(%s) gid=%s groups=%s\n"):format(u.uid, u.name, primary, table.concat(groups, ",")))
return 0
