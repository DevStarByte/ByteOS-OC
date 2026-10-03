-- groups [user] - print the groups a user is in
local auth = require("auth")
local name = (arg or {})[1] or k.user()
if not auth.user(fs, name) then term.write("groups: '" .. name .. "': no such user\n"); return 1 end
local names = {}
for _, g in ipairs(auth.groupsOf(fs, name)) do names[#names + 1] = g.name end
term.write(table.concat(names, " ") .. "\n")
return 0
