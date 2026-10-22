--[[
  zcat - show what is in .gz files (the same as gzip -dc)

    zcat FILE.gz...      their unpacked contents, one after another
    zcat notes.gz | grep todo
]]--
local words = { "gzip", "-dc" }
for _, a in ipairs(arg or {}) do words[#words + 1] = "'" .. a:gsub("'", "'\\''") .. "'" end
return shell.run(table.concat(words, " "), stdio)
