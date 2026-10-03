--[[
  /lib/files.lua - copying files and whole directories (cp, mv)

    files.copy(src, dst, recursive) -> true | nil, reason
        a directory needs `recursive`; dst must not lie inside src
    files.join(dir, name) -> "dir/name" (also for dir = "/")
]]--
local fs = kernel.fs
local files = {}

function files.join(dir, name)
  return (dir == "/" and "" or dir) .. "/" .. name
end

function files.copy(src, dst, recursive)
  if fs.isDirectory(src) then
    if not recursive then return nil, src .. " is a directory (use -r)" end
    if dst == src or dst:sub(1, #src + 1) == src .. "/" then
      return nil, "cannot copy " .. src .. " into itself"
    end
    if not fs.exists(dst) then
      local ok, e = fs.makeDirectory(dst)
      if not ok then return nil, "cannot create " .. dst .. (e and (": " .. e) or "") end
    elseif not fs.isDirectory(dst) then
      return nil, dst .. " is not a directory"
    end
    for _, n in ipairs(fs.list(src)) do
      n = n:gsub("/$", "")
      local ok, e = files.copy(files.join(src, n), files.join(dst, n), true)
      if not ok then return nil, e end
    end
    return true
  end
  local data, e = fs.readAll(src)
  if not data then return nil, src .. ": " .. tostring(e) end
  local ok, werr = fs.writeAll(dst, data)
  if not ok then return nil, "cannot create " .. dst .. ": " .. tostring(werr) end
  return true
end

return files
