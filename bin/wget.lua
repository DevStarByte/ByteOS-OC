--[[
  wget [-O file] [-q] URL - download a file through the internet card

    -O file   save as file (default: the name at the end of the URL);
              -O - writes it to the output instead
    -q        no progress line
]]--
local internet = require("internet")
local units = require("units")
local args = arg or {}
local out, quiet, url
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-O" then i = i + 1; out = args[i]
  elseif a == "-q" then quiet = true
  else url = a end
  i = i + 1
end
if not url then term.write("usage: wget [-O file] [-q] URL\n"); return 1 end
if not url:match("^https?://") then url = "http://" .. url end
if not internet.available() then term.write("wget: no internet card installed\n"); return 1 end

if out == "-" then
  local ok, err = internet.get(url, function(c) term.write(c) end)
  if not ok then term.write("wget: " .. tostring(err) .. "\n"); return 1 end
  return 0
end
out = out or url:match("^[^?#]*/([^/?#]+)$") or "index.html"
local path = shell.normalize(out)
local f, err = fs.open(path, "w")
if not f then term.write("wget: " .. out .. ": " .. tostring(err) .. "\n"); return 1 end
if not quiet then term.write("Downloading " .. url .. "\n") end
local got = 0
local ok, gerr = internet.get(url, function(c)
  f:write(c)
  got = got + #c
  if not quiet then term.write("\r  " .. units.bytes(got) .. " ") end
end)
f:close()
if not ok then
  fs.remove(path)
  term.write("\nwget: " .. tostring(gerr) .. "\n")
  return 1
end
if not quiet then term.write("\rSaved " .. out .. " (" .. units.bytes(got) .. ")\n") end
return 0
