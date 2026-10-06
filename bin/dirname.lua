--[[
  dirname PATH... - the directory part of each PATH

    dirname /etc/pacman.conf    /etc
    dirname notes.txt           .
]]--
local args = arg or {}
if not args[1] then term.write("usage: dirname PATH...\n"); return 1 end
for _, a in ipairs(args) do
  local p = a:gsub("/+$", "")
  local dir
  if p == "" then dir = "/"
  elseif not p:find("/") then dir = "."
  else dir = p:match("^(.*)/[^/]*$"):gsub("/+$", "") end
  term.write((dir == "" and "/" or dir) .. "\n")
end
return 0
