--[[
  nl [-b a|t] [-w N] [-s SEP] [FILE...]   print lines with line numbers

    -b t     number only lines that are not empty (the default)
    -b a     number every line
    -w N     numbers N characters wide (default 6)
    -s SEP   what comes between number and line (default a tab)
]]--
local args = arg or {}
local style, width, sep, files = "t", 6, "\t", {}
local i = 1
while i <= #args do
  local a = args[i]
  local opt, val = a:match("^%-([bws])(.*)$")
  if opt then
    if val == "" then i = i + 1; val = args[i] or "" end
    if opt == "b" then style = val elseif opt == "w" then width = tonumber(val) else sep = val end
  else files[#files + 1] = a end
  i = i + 1
end
if (style ~= "a" and style ~= "t") or not width then term.write("usage: nl [-b a|t] [-w N] [-s SEP] [FILE...]\n"); return 1 end
if #files == 0 then files = { "-" } end
local n, rc = 0, 0
for _, f in ipairs(files) do
  local text, err
  if f == "-" then text = stdin.read("a") or "" else text, err = fs.readAll(shell.normalize(f)) end
  if not text then term.write("nl: " .. f .. ": " .. tostring(err or "no such file") .. "\n"); rc = 1
  elseif text ~= "" then
    if text:sub(-1) ~= "\n" then text = text .. "\n" end
    local out = {}
    for line in text:gmatch("([^\n]*)\n") do
      if style == "a" or line ~= "" then
        n = n + 1
        out[#out + 1] = ("%" .. width .. "d"):format(n) .. sep .. line
      else
        out[#out + 1] = string.rep(" ", width + #sep) .. line
      end
    end
    term.write(table.concat(out, "\n") .. "\n")
  end
end
return rc
