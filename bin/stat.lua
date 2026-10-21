--[[
  stat [-c FORMAT] FILE...   what is known about a file

    File, size, type, owner, group and permissions, and when the disk
    keeps it, the time it was last changed.

    -c FORMAT   print only FORMAT for each file, with
                %n name   %N name -> target (links)   %s size in bytes
                %F type   %a mode in octal   %A mode as in ls -l
                %U owner  %G group   %% a %

    stat -c '%a %U' /etc/shadow      600 root
]]--
local args = arg or {}
local format, files = nil, {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-c" or a == "--format" then i = i + 1; format = args[i]
  elseif a:match("^%-%-format=") then format = a:match("=(.*)$")
  else files[#files + 1] = a end
  i = i + 1
end
if #files == 0 or (format == nil and args[#args] == "-c") then term.write("usage: stat [-c FORMAT] FILE...\n"); return 1 end

local function modeString(mode)
  local s = {}
  for shift = 6, 0, -3 do
    local b = (mode >> shift) & 7
    s[#s + 1] = (b & 4 ~= 0 and "r" or "-") .. (b & 2 ~= 0 and "w" or "-") .. (b & 1 ~= 0 and "x" or "-")
  end
  return table.concat(s)
end

local rc = 0
for _, f in ipairs(files) do
  local p = shell.normalize(f)
  local link = fs.readlink and fs.readlink(p)
  if not link and not fs.exists(p) then
    term.write("stat: cannot stat '" .. f .. "': no such file or directory\n"); rc = 1
  else
    local dir = not link and fs.isDirectory(p)
    local st = fs.stat(p)
    local size = link and #link or (dir and 0 or (fs.size(p) or 0))
    local kind = link and "symbolic link" or dir and "directory" or "regular file"
    local mode = link and 511 or st.mode
    local typeChar = link and "l" or dir and "d" or "-"
    local values = {
      n = f, N = link and ("'" .. f .. "' -> '" .. link .. "'") or ("'" .. f .. "'"),
      s = tostring(size), F = kind, a = ("%o"):format(mode), A = typeChar .. modeString(mode),
      U = st.owner, G = st.group, ["%"] = "%",
    }
    if format then
      local bad
      local text = format:gsub("%%(.)", function(c)
        if values[c] then return values[c] end
        bad = bad or c
      end)
      if bad then term.write("stat: unknown format %" .. bad .. "\n"); return 1 end
      text = text:gsub("\\n", "\n"):gsub("\\t", "\t")
      term.write(text .. "\n")
    else
      term.write("  File: " .. f .. (link and (" -> " .. link) or "") .. "\n")
      term.write(("  Size: %-12s %s\n"):format(size, kind))
      term.write(("Access: (%04o/%s)  Uid: %s  Gid: %s\n"):format(mode, values.A, st.owner, st.group))
      local proxy, sub = fs.resolve(p)
      local ms = proxy and proxy.lastModified and not link and proxy.lastModified(sub)
      if ms and ms > 0 then
        term.write("Modify: " .. os.date("!%Y-%m-%d %H:%M:%S UTC", ms // 1000) .. "\n")
      end
    end
  end
end
return rc
