-- hostname [name] - show the computer's name; root may set a new one
local name = (arg or {})[1]
if not name then term.write((_G.HOSTNAME or "byteos") .. "\n"); return 0 end
if k.user() ~= "root" then term.write("hostname: you must be root to change the host name\n"); return 1 end
if not name:match("^[%w][%w%-_]*$") then term.write("hostname: use only letters, digits, - and _\n"); return 1 end
local ok, err = fs.writeAll("/etc/hostname", name .. "\n")
if not ok then term.write("hostname: " .. tostring(err) .. "\n"); return 1 end
_G.HOSTNAME = name
return 0
