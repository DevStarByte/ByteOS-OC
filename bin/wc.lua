-- wc [-l] [-w] [-c] [file...] - count lines, words and bytes of each file,
-- or of the input without files
local args = arg or {}
local opt, files = {}, {}
for _, a in ipairs(args) do
  if a:match("^%-%a+$") then for f in a:sub(2):gmatch(".") do opt[f] = true end
  else files[#files + 1] = a end
end
if not (opt.l or opt.w or opt.c) then opt.l, opt.w, opt.c = true, true, true end
local useStdin = #files == 0
if useStdin then files = { "-" } end
local total = { 0, 0, 0 }
local function show(l, w, c, name)
  local parts = {}
  if opt.l then parts[#parts + 1] = ("%7d"):format(l) end
  if opt.w then parts[#parts + 1] = ("%7d"):format(w) end
  if opt.c then parts[#parts + 1] = ("%7d"):format(c) end
  term.write(table.concat(parts, " ") .. (name and (" " .. name) or "") .. "\n")
end
for _, f in ipairs(files) do
  local text, err
  if f == "-" then text = stdin.read("a") or ""
  else text, err = k.fs.readAll(shell.normalize(f)) end
  if not text then term.write("wc: " .. f .. ": " .. tostring(err or "no such file") .. "\n"); return 1 end
  -- counted without gsub, which would build a copy of the text
  local l, w = 0, 0
  for _ in text:gmatch("\n") do l = l + 1 end
  for _ in text:gmatch("%S+") do w = w + 1 end
  show(l, w, #text, not useStdin and f or nil)
  total[1], total[2], total[3] = total[1] + l, total[2] + w, total[3] + #text
end
if #files > 1 then show(total[1], total[2], total[3], "total") end
return 0
