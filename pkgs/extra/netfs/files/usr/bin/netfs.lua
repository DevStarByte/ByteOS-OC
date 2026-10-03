--[[
  netfs - shared folders on other computers

    netfs                              what is mounted from where
    netfs shares <host>                the folders host shares
    netfs mount <host>:<share> <dir>   use one as <dir> (root), e.g.
                                       sudo netfs mount server:public /mnt/pub
    netfs umount <dir>                 stop using it (root)

  To share folders yourself, list them in /etc/netfs.conf (netfsd, a
  service, answers the others). A mount lasts until the next reboot.
]]--
local netfs = require("netfs")
local T = term.theme
local args = arg or {}
local cmd = args[1]

local function fail(msg) term.cwrite(T.err, "netfs: "); term.write(tostring(msg) .. "\n"); return 1 end
local function absolute(dir)
  if dir:sub(1, 1) ~= "/" then dir = (_G.PWD or "/") .. "/" .. dir end
  dir = dir:gsub("/+", "/"):gsub("(.)/$", "%1")
  return dir
end

if not cmd then
  local list = netfs.mounted()
  if #list == 0 then term.write("Nothing mounted. See: netfs shares <host>\n"); return 0 end
  for _, m in ipairs(list) do
    term.cwrite(T.blue, m.path)
    term.write(("  %s:%s (%s)\n"):format(m.host, m.share, m.mode))
  end
  return 0
elseif cmd == "shares" then
  if not args[2] then return fail("usage: netfs shares <host>") end
  local list, err = netfs.shares(args[2])
  if not list then return fail(err) end
  if #list == 0 then term.write(args[2] .. " shares nothing (see its /etc/netfs.conf)\n"); return 0 end
  for _, s in ipairs(list) do term.write(("%-16s %s\n"):format(s.name, s.mode)) end
  return 0
elseif cmd == "mount" then
  local host, share = (args[2] or ""):match("^([^:]+):(.+)$")
  local dir = args[3]
  if not host or not dir then return fail("usage: netfs mount <host>:<share> <dir>") end
  if k.user() ~= "root" then return fail("only root may mount (try sudo)") end
  dir = absolute(dir)
  if dir == "/" then return fail("cannot mount over /") end
  for _, m in ipairs(fs.mounts()) do
    if m.path == dir then return fail(dir .. " is already a mount point") end
  end
  local list, addr, name = netfs.shares(host)
  if not list then return fail(addr) end
  local mode
  for _, s in ipairs(list) do if s.name == share then mode = s.mode end end
  if not mode then return fail(host .. " has no share " .. share) end
  local ok, err = fs.mount(dir, netfs.proxy(addr, name, share, mode))
  if not ok then return fail(err) end
  term.write(("Mounted %s:%s on %s (%s)\n"):format(name, share, dir, mode))
  return 0
elseif cmd == "umount" or cmd == "unmount" then
  if not args[2] then return fail("usage: netfs umount <dir>") end
  if k.user() ~= "root" then return fail("only root may unmount (try sudo)") end
  local dir = absolute(args[2])
  for _, m in ipairs(netfs.mounted()) do
    if m.path == dir then fs.umount(dir); term.write("Unmounted " .. dir .. "\n"); return 0 end
  end
  return fail(dir .. " is not a netfs mount")
end
return fail("unknown command " .. cmd .. " (see man netfs)")
