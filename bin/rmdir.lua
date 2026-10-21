--[[
  rmdir [-p] DIR...   remove empty directories

    -p   remove the parents too, as long as they become empty
         (rmdir -p a/b/c removes c, then b, then a)

  A directory that still holds something is left alone; rm -r removes
  everything in it.
]]--
local args = arg or {}
local parents, dirs = false, {}
for _, a in ipairs(args) do
  if a == "-p" or a == "--parents" then parents = true
  elseif a:sub(1, 1) == "-" and #a > 1 then term.write("rmdir: unknown option " .. a .. "\n"); return 1
  else dirs[#dirs + 1] = a end
end
if #dirs == 0 then term.write("usage: rmdir [-p] DIR...\n"); return 1 end

-- false and a message, or true
local function removeOne(shown, p)
  if not fs.exists(p) then return false, "no such file or directory" end
  if not fs.isDirectory(p) or (fs.readlink and fs.readlink(p)) then return false, "not a directory" end
  if #(fs.list(p) or {}) > 0 then return false, "Directory not empty" end
  local ok, err = fs.remove(p)
  if not ok then return false, tostring(err or "failed") end
  return true
end

local rc = 0
for _, d in ipairs(dirs) do
  local shown = d:gsub("/+$", "")
  if shown == "" then shown = "/" end
  while true do
    local ok, err = removeOne(shown, shell.normalize(shown))
    if not ok then
      term.write("rmdir: failed to remove '" .. shown .. "': " .. err .. "\n"); rc = 1; break
    end
    if not parents then break end
    local up = shown:match("^(.*)/[^/]*$")
    if not up or up == "" or up == "." or up == ".." then break end
    shown = up
  end
end
return rc
