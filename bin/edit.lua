-- edit - tiny line editor
local args = arg or {}
if #args == 0 then term.write("usage: edit <file>\n"); return 1 end
local path = shell.normalize(args[1])
local lines = {}
if k.fs.exists(path) then
  for ln in (k.fs.readAll(path) or ""):gmatch("([^\n]*)\n?") do lines[#lines+1] = ln end
  if lines[#lines] == "" then lines[#lines] = nil end
end
term.write("byteedit - commands: :w save, :q quit, :wq save+quit, :p print, :a append, :d <n> delete line\n")
while true do
  term.write("> ")
  local line = term.read()
  if not line then break end
  if line == ":q" then return 0
  elseif line == ":w" then k.fs.writeAll(path, table.concat(lines, "\n") .. "\n"); term.write("written " .. #lines .. " lines\n")
  elseif line == ":wq" then k.fs.writeAll(path, table.concat(lines, "\n") .. "\n"); return 0
  elseif line == ":p" then for i, l in ipairs(lines) do term.write(string.format("%4d  %s\n", i, l)) end
  elseif line == ":a" then
    while true do
      term.write(". ")
      local l = term.read()
      if not l or l == "." then break end
      lines[#lines+1] = l
    end
  elseif line:sub(1, 3) == ":d " then
    local n = tonumber(line:sub(4))
    if n then table.remove(lines, n) end
  else
    lines[#lines+1] = line
  end
end
return 0
