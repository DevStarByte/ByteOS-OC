--[[
  grep [-i] [-v] [-n] [-c] [-F] pattern [file...] - print matching lines

    -i  ignore case        -v  lines that do NOT match
    -n  line numbers       -c  only count the matching lines
    -F  match the pattern as plain text

  Patterns are Lua patterns: . any character, %d digit, %a letter, * + -
  repeat, ^ $ anchor (see the Lua manual). Without files, grep reads its
  input: `ls /bin | grep pac`. Exit status 0 if a line matched, 1 if not.
]]--
local args = arg or {}
local T = term.theme
local opt, files, pattern = {}, {}, nil
for _, a in ipairs(args) do
  if a:match("^%-%a+$") and not pattern then
    for f in a:sub(2):gmatch(".") do opt[f] = true end
  elseif not pattern then pattern = a
  else files[#files + 1] = a end
end
if not pattern then term.write("usage: grep [-i] [-v] [-n] [-c] [-F] pattern [file...]\n"); return 2 end
if opt.i then pattern = pattern:lower() end
local okPat, perr = pcall(string.find, "", pattern, 1, opt.F)
if not okPat then term.write("grep: bad pattern: " .. tostring(perr) .. "\n"); return 2 end
if #files == 0 then files = { "-" } end

local found = false
for _, f in ipairs(files) do
  local text
  if f == "-" then
    text = stdin.read("a") or ""
  else
    local err
    text, err = k.fs.readAll(shell.normalize(f))
    if not text then term.write("grep: " .. f .. ": " .. tostring(err or "no such file") .. "\n"); return 2 end
  end
  local count, n = 0, 0
  -- line by line through the text itself (no copy of it: it can be large)
  local pos, len = 1, #text
  while pos <= len do
    local e = text:find("\n", pos, true) or len + 1
    local line = text:sub(pos, e - 1)
    pos = e + 1
    n = n + 1
    local hay = opt.i and line:lower() or line
    local hit = hay:find(pattern, 1, opt.F) ~= nil
    if hit ~= (opt.v == true) then
      count = count + 1
      found = true
      if not opt.c then
        if #files > 1 then term.cwrite(T.magenta, f .. ":") end
        if opt.n then term.cwrite(T.green, n .. ":") end
        term.write(line .. "\n")
      end
    end
  end
  if opt.c then term.write((#files > 1 and (f .. ":") or "") .. count .. "\n") end
end
return found and 0 or 1
