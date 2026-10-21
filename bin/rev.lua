-- rev [FILE...] - print each line with its characters in reverse order
local args = arg or {}
local files = #args > 0 and args or { "-" }
local rc = 0
for _, f in ipairs(files) do
  local text, err
  if f == "-" then text = stdin.read("a") or "" else text, err = fs.readAll(shell.normalize(f)) end
  if not text then term.write("rev: " .. f .. ": " .. tostring(err or "no such file") .. "\n"); rc = 1
  elseif text ~= "" then
    if text:sub(-1) ~= "\n" then text = text .. "\n" end
    local out = {}
    for line in text:gmatch("([^\n]*)\n") do
      local chars = {}
      for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do table.insert(chars, 1, ch) end
      out[#out + 1] = table.concat(chars)
    end
    term.write(table.concat(out, "\n") .. "\n")
  end
end
return rc
