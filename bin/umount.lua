-- umount <path|disk> - unmount a filesystem (root); / stays mounted
local target = (arg or {})[1]
if not target then term.write("usage: umount <path|disk>\n"); return 1 end
local path = target:sub(1, 1) == "/" and shell.normalize(target) or nil
for _, m in ipairs(k.fs.mounts()) do
  if m.path == path or (not path and m.proxy.address:sub(1, #target) == target) then
    if m.path == "/" then term.write("umount: /: the root filesystem cannot be unmounted\n"); return 1 end
    local ok, err = k.fs.umount(m.path)
    if not ok then term.write("umount: " .. tostring(err) .. "\n"); return 1 end
    return 0
  end
end
term.write("umount: " .. target .. ": not mounted\n")
return 1
