--[[
  realpath PATH... - the full path of each PATH, links followed

    realpath ../notes.txt       /home/alice/notes.txt
    realpath ~/music            /mnt/1a2b3c4d/music  (when ~/music is a link)

  A path that does not exist is an error (status 1).
]]--
local args = arg or {}
if #args == 0 then term.write("usage: realpath PATH...\n"); return 1 end
local rc = 0
for _, p in ipairs(args) do
  local real, err = fs.realpath(shell.normalize(p))
  if real and fs.exists(real) then term.write(real .. "\n")
  else term.write("realpath: " .. p .. ": " .. (err or "no such file or directory") .. "\n"); rc = 1 end
end
return rc
