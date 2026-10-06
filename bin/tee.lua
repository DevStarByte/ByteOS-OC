--[[
  tee [-a] FILE... - copy the input to each FILE and to the output

    -a   add to the files instead of replacing them

  Saves what a command prints while still showing it:
    pacman -Qi byteos | tee /tmp/info.txt
]]--
local args = arg or {}
local append, files = false, {}
for _, a in ipairs(args) do
  if a == "-a" then append = true else files[#files + 1] = a end
end
local text = stdin.read("a") or ""
local rc = 0
for _, f in ipairs(files) do
  local path, ok, err = shell.normalize(f), nil, nil
  if append then
    local h
    h, err = fs.open(path, "a")
    if h then h:write(text); h:close(); ok = true end
  else
    ok, err = fs.writeAll(path, text)
  end
  if not ok then term.write("tee: " .. f .. ": " .. tostring(err) .. "\n"); rc = 1 end
end
term.write(text)
return rc
