-- head [-n N | -N] [file...] - the first N lines (default 10) of each file,
-- or of the input without files
local args = arg or {}
local n, files = 10, {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-n" then i = i + 1; n = tonumber(args[i]) or n
  elseif a:match("^%-%d+$") then n = tonumber(a:sub(2))
  else files[#files + 1] = a end
  i = i + 1
end
if #files == 0 then files = { "-" } end
for idx, f in ipairs(files) do
  local text, err
  if f == "-" then text = stdin.read("a") or ""
  else text, err = k.fs.readAll(shell.normalize(f)) end
  if not text then term.write("head: " .. f .. ": " .. tostring(err or "no such file") .. "\n"); return 1 end
  if #files > 1 then term.write((idx > 1 and "\n" or "") .. "==> " .. f .. " <==\n") end
  local count = 0
  for line in text:gmatch("[^\n]*\n?") do
    if line == "" or count >= n then break end
    term.write(line)
    count = count + 1
  end
end
return 0
