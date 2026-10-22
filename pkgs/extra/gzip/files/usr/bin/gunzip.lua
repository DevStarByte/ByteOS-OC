--[[
  gunzip - unpack .gz files (the same as gzip -d)

    gunzip FILE.gz...   FILE.gz becomes FILE (.tgz becomes .tar)
    -c -k -f -v         as for gzip: man gzip
    ... | gunzip        unpack the input into the output
]]--
local words = { "gzip", "-d" }
for _, a in ipairs(arg or {}) do words[#words + 1] = "'" .. a:gsub("'", "'\\''") .. "'" end
return shell.run(table.concat(words, " "), stdio)
