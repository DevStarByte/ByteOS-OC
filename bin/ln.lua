--[[
  ln -s [-f] [-n] TARGET LINK - make a symbolic link

    ln -s /mnt/1a2b3c4d/music ~/music     ~/music leads to the disk
    ln -s ../lib/tool.lua bin/tool.lua    relative: from the link's directory
    ln -s /etc/motd /tmp/                 into a directory: /tmp/motd

    -f  replace a LINK that is already there
    -n  a LINK that is a link to a directory is replaced, not entered

  The link is followed wherever it is used: cat, cd, ls, editors. rm and
  mv act on the link itself. readlink shows where it points; ls -l too.
  There are no hard links: OpenComputers' disks cannot share a file.
]]--
local args = arg or {}
local opt, paths = {}, {}
for _, a in ipairs(args) do
  if a:match("^%-%a+$") then for f in a:sub(2):gmatch(".") do opt[f] = true end
  else paths[#paths + 1] = a end
end
if not opt.s then term.write("ln: hard links are not supported, use ln -s\n"); return 1 end
if #paths ~= 2 then term.write("usage: ln -s [-f] [-n] TARGET LINK\n"); return 1 end
local target, link = paths[1], shell.normalize(paths[2])
-- an existing directory (also through a link, unless -n) takes the link inside
if fs.isDirectory(link) and not (opt.n and fs.readlink(link)) then
  link = (link == "/" and "" or link) .. "/" .. (target:gsub("/+$", ""):match("[^/]*$"))
end
if opt.f and (fs.readlink(link) or (fs.exists(link) and not fs.isDirectory(link))) then
  local ok, err = fs.remove(link)
  if not ok then term.write("ln: cannot replace '" .. link .. "': " .. tostring(err) .. "\n"); return 1 end
end
local ok, err = fs.link(target, link)
if not ok then term.write("ln: cannot create '" .. link .. "': " .. tostring(err) .. "\n"); return 1 end
return 0
