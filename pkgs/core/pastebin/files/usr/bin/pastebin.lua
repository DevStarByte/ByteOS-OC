--[[
  pastebin - get programs from pastebin.com, run them, share your own

    pastebin get CODE FILE     download paste CODE into FILE (-f overwrites)
    pastebin run CODE [ARGS]   download it and run it, with ARGS
    pastebin put FILE          upload FILE (unlisted) and print its address

  CODE is the part after pastebin.com/ (as in pastebin.com/x8Kq2Rt4), or
  the whole address. Uploading needs a pastebin developer key: sign in on
  pastebin.com, open https://pastebin.com/doc_api and copy "Your Unique
  Developer API Key", then put it in /etc/pastebin.conf as

    key = 0123456789abcdef...

  or in the variable PASTEBIN_KEY (set PASTEBIN_KEY ... in ~/.shrc).
  Programs written for OpenOS may need libraries ByteOS does not have.
]]--
local args = arg or {}
local internet = require("internet")

local function err(msg) term.write("pastebin: " .. msg .. "\n") end
local function usage()
  term.write("usage: pastebin get CODE FILE | pastebin run CODE [ARGS...] | pastebin put FILE\n")
  return 2
end

local force, words = false, {}
for _, a in ipairs(args) do
  if a == "-f" then force = true else words[#words + 1] = a end
end
local action = table.remove(words, 1)
if not action then return usage() end
if not internet.available() then err("no internet card"); return 1 end

-- "x8Kq2Rt4", "pastebin.com/x8Kq2Rt4", "https://pastebin.com/raw/x8Kq2Rt4" -> "x8Kq2Rt4"
local function codeOf(s)
  local code = s:gsub("[?#].*$", ""):gsub("/+$", ""):match("([%w]+)$")
  if not code or (s:find("/") and not s:find("pastebin%.com")) then return nil end
  return code
end

local function download(code)
  local text, why, status = internet.fetch("https://pastebin.com/raw/" .. code)
  if not text then
    if status == 404 then return nil, "no paste " .. code end
    return nil, tostring(why)
  end
  return text
end

if action == "get" then
  local code, file = words[1] and codeOf(words[1]), words[2]
  if not code or not file then return usage() end
  local path = shell.normalize(file)
  if fs.exists(path) and not force then err(file .. " exists (-f overwrites it)"); return 1 end
  term.write("Downloading " .. code .. " ...\n")
  local text, why = download(code)
  if not text then err(why); return 1 end
  local ok, werr = fs.writeAll(path, text)
  if not ok then err(file .. ": " .. tostring(werr)); return 1 end
  term.write(("Saved %s (%d bytes)\n"):format(file, #text))
  return 0

elseif action == "run" then
  local code = words[1] and codeOf(words[1])
  if not code then return usage() end
  local text, why = download(code)
  if not text then err(why); return 1 end
  local path = "/tmp/pastebin-" .. code .. ".lua"
  local ok, werr = fs.writeAll(path, text)
  if not ok then err(path .. ": " .. tostring(werr)); return 1 end
  local line = { "'" .. path .. "'" }
  for i = 2, #words do line[#line + 1] = "'" .. words[i]:gsub("'", "'\\''") .. "'" end
  return shell.run(table.concat(line, " "), stdio)

elseif action == "put" then
  local file = words[1]
  if not file then return usage() end
  local text, rerr = fs.readAll(shell.normalize(file))
  if not text then err(file .. ": " .. tostring(rerr)); return 1 end
  local key = _G.PASTEBIN_KEY
  if not key or key == "" then
    local conf = fs.exists("/etc/pastebin.conf") and fs.readAll("/etc/pastebin.conf") or ""
    for line in conf:gmatch("[^\r\n]+") do
      key = line:match("^%s*key%s*=%s*(%S+)") or key
    end
  end
  if not key or key == "" then
    err("uploading needs your pastebin developer key (man pastebin):")
    term.write("  sign in on pastebin.com, copy the key from https://pastebin.com/doc_api\n")
    term.write("  and put  key = <it>  into /etc/pastebin.conf (or set PASTEBIN_KEY)\n")
    return 1
  end
  local function enc(s)
    return (s:gsub("[^%w%-_%.~]", function(c) return ("%%%02X"):format(c:byte()) end))
  end
  local body = table.concat({
    "api_option=paste", "api_dev_key=" .. enc(key), "api_paste_private=1",
    "api_paste_name=" .. enc(file:match("[^/]*$")), "api_paste_code=" .. enc(text),
  }, "&")
  local card = component.proxy(component.list("internet")())
  local ok, h, why = pcall(card.request, "https://pastebin.com/api/api_post.php", body,
    { ["Content-Type"] = "application/x-www-form-urlencoded", ["User-Agent"] = "ByteOS" })
  if not ok or not h then err(tostring(ok and why or h)); return 1 end
  local deadline = computer.uptime() + 20
  while true do
    local okc, done, cerr = pcall(h.finishConnect)
    if not okc or done == nil then pcall(h.close); err(tostring(okc and cerr or done)); return 1 end
    if done then break end
    if computer.uptime() > deadline then pcall(h.close); err("the connection timed out"); return 1 end
    k.event.pull(0.05)
  end
  local parts = {}
  while true do
    local okr, chunk = pcall(h.read, 8192)
    if not okr or chunk == nil then break end
    if chunk == "" then
      if computer.uptime() > deadline then break end
      k.event.pull(0.05)
    else
      parts[#parts + 1] = chunk
    end
  end
  pcall(h.close)
  local answer = table.concat(parts):gsub("^%s+", ""):gsub("%s+$", "")
  if answer:match("^https?://") then
    term.write("Uploaded as " .. answer .. "\n")
    term.write("Get it elsewhere with: pastebin get " .. (codeOf(answer) or "?") .. " " .. file:match("[^/]*$") .. "\n")
    return 0
  end
  err("pastebin said: " .. (answer ~= "" and answer or "nothing"))
  return 1
end
return usage()
