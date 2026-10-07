--[[
  mount                   list what is mounted where
  mount <disk> <path>     mount a disk (address prefix or label) at path (root)

  Disks are mounted at /mnt/<first 8 characters of the address> by
  themselves, also when inserted later; see lsblk.
]]--
local args = arg or {}
if #args == 0 then
  local list = k.fs.mounts()
  table.sort(list, function(a, b) return a.path < b.path end)
  for _, m in ipairs(list) do
    local p = m.proxy
    local label = p.getLabel and p.getLabel()
    term.write(p.address:sub(1, 8) .. " on " .. m.path .. " (" .. ((p.isReadOnly and p.isReadOnly()) and "ro" or "rw")
      .. (label and (", " .. label) or "") .. ")\n")
  end
  return 0
end
local dev, path = args[1], args[2]
if not path then term.write("usage: mount [<disk> <path>]\n"); return 1 end
local found
for addr in component.list("filesystem") do
  local p = component.proxy(addr)
  if addr:sub(1, #dev) == dev or (p.getLabel and p.getLabel() == dev) then
    if found then term.write("mount: '" .. dev .. "' matches more than one disk\n"); return 1 end
    found = p
  end
end
if not found then term.write("mount: no disk '" .. dev .. "' (see lsblk)\n"); return 1 end
local ok, err = k.fs.mount(shell.normalize(path), found)
if not ok then term.write("mount: " .. tostring(err) .. "\n"); return 1 end
return 0
