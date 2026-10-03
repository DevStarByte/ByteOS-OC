--[[
  curl [-o file] [-s] URL - fetch a URL and print it (or save it with -o)

    -s   silent: no error messages
  e.g. curl example.com | head
]]--
local internet = require("internet")
local args = arg or {}
local out, silent, url
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-o" then i = i + 1; out = args[i]
  elseif a == "-s" then silent = true
  else url = a end
  i = i + 1
end
local function fail(msg) if not silent then term.write("curl: " .. msg .. "\n") end return 1 end
if not url then return fail("usage: curl [-o file] [-s] URL") end
if not url:match("^https?://") then url = "http://" .. url end
if not internet.available() then return fail("no internet card installed") end
local f
if out then
  local err
  f, err = fs.open(shell.normalize(out), "w")
  if not f then return fail(out .. ": " .. tostring(err)) end
end
local ok, err = internet.get(url, function(c) if f then f:write(c) else term.write(c) end end)
if f then f:close() end
if not ok then return fail(tostring(err)) end
return 0
