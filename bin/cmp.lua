--[[
  cmp [-s] FILE1 FILE2   compare two files byte by byte

    Prints where they first differ ("a b differ: byte 5, line 2") and
    exits with 1; exits with 0 when they are the same, 2 on trouble.
    -s   print nothing, only the exit status

  - as a file name reads the input.
]]--
local args = arg or {}
local silent, files = false, {}
for _, a in ipairs(args) do
  if a == "-s" or a == "--quiet" or a == "--silent" then silent = true else files[#files + 1] = a end
end
if #files ~= 2 then term.write("usage: cmp [-s] FILE1 FILE2\n"); return 2 end
local data = {}
for n, f in ipairs(files) do
  local text, err
  if f == "-" then text = stdin.read("a") or "" else text, err = fs.readAll(shell.normalize(f)) end
  if not text then
    if not silent then term.write("cmp: " .. f .. ": " .. tostring(err or "no such file") .. "\n") end
    return 2
  end
  data[n] = text
end
local a, b = data[1], data[2]
if a == b then return 0 end
local len = math.min(#a, #b)
local pos = len + 1
for i = 1, len do
  if a:byte(i) ~= b:byte(i) then pos = i; break end
end
if silent then return 1 end
if pos > len then
  term.write(("cmp: EOF on %s after byte %d\n"):format(#a < #b and files[1] or files[2], len))
else
  local _, newlines = a:sub(1, pos - 1):gsub("\n", "")
  term.write(("%s %s differ: byte %d, line %d\n"):format(files[1], files[2], pos, newlines + 1))
end
return 1
