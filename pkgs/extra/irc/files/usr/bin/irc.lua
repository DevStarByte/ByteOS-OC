--[[
  irc - chat on IRC through the internet card

    irc [-n NICK] [-p PORT] [-j CHANNEL]... [SERVER] ['#CHANNEL'...]

  Connects to SERVER (default irc.libera.chat, port 6667) as NICK (default
  your user name) and joins the channels: -j byteos, or '#byteos' in
  quotes (an unquoted # starts a comment in the shell).

    irc -j byteos                    irc -n alice irc.libera.chat '#byteos'

  The screen shows the server and where you talk at the top, the messages
  below and your line at the bottom. A line without / goes to the current
  channel (or person).

    /join #chan        join a channel, or switch to one you are in
    /part [#chan]      leave it          /query NICK   talk to one person
    /msg NICK TEXT     one message       /me TEXT      an action
    /nick NEW          another nick      /names        who is here
    /topic [TEXT]      show or set the topic
    /quote LINE        send a raw IRC line
    /clear             empty the screen  /quit [TEXT]  leave (or Ctrl+C)

  ↑ ↓ bring back what you typed, PgUp PgDn scroll. Messages that mention
  your nick are yellow. The connection is plain TCP (OpenComputers has no
  TLS for it), so use servers that take it on 6667; the internet card must
  be allowed to open TCP connections in the server's OpenComputers config.
]]--
local args = arg or {}
local T = term.theme
local clock = require("clock")

local nick, port, server = _G.USER or "byteos", 6667, "irc.libera.chat"
local autojoin = {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-n" then i = i + 1; nick = args[i]
  elseif a == "-p" then i = i + 1; port = tonumber(args[i])
  elseif a == "-j" then
    i = i + 1
    local ch = args[i]
    if not ch then term.write("irc: -j needs a channel\n"); return 2 end
    autojoin[#autojoin + 1] = (ch:sub(1, 1) == "#" or ch:sub(1, 1) == "&") and ch or ("#" .. ch)
  elseif a:sub(1, 1) == "#" or a:sub(1, 1) == "&" then autojoin[#autojoin + 1] = a
  elseif a:sub(1, 1) == "-" then term.write("irc: unknown option " .. a .. "\n"); return 2
  else server = a end
  i = i + 1
end
if not nick or not nick:match("^[%a%[%]\\`_%^{|}][%w%[%]\\`_%^{|}%-]*$") then
  term.write("irc: not a usable nick: " .. tostring(nick) .. " (letters, digits and []\\`_^{|}-)\n"); return 2
end
if not port then term.write("irc: -p needs a port number\n"); return 2 end

local addr = component.list("internet")()
local inet = addr and component.proxy(addr)
if not inet then term.write("irc: no internet card\n"); return 1 end
if not inet.connect then term.write("irc: this internet card cannot open TCP connections\n"); return 1 end

-- ---- connecting ------------------------------------------------------------------
term.write(("Connecting to %s:%d ...\n"):format(server, port))
local okc, sock, cerr = pcall(inet.connect, server, port)
if not okc or not sock then term.write("irc: " .. tostring(okc and cerr or sock) .. "\n"); return 1 end
local deadline = computer.uptime() + 20
while true do
  local ok, done, why = pcall(sock.finishConnect)
  if not ok or done == nil then
    term.write("irc: cannot connect: " .. tostring(ok and why or done) .. "\n"); pcall(sock.close); return 1
  end
  if done then break end
  if computer.uptime() > deadline then term.write("irc: the connection timed out\n"); pcall(sock.close); return 1 end
  k.event.pull(0.1)
end

local function send(line) pcall(sock.write, line .. "\r\n") end

-- ---- what is on the screen -----------------------------------------------------------
local MAXLINES = 300
local lines = {}        -- { time, parts = { { text, colour }, ... } }
local scroll = 0        -- rows scrolled back from the newest
local me = nick
local target            -- where a plain line goes: a channel or a nick
local channels = {}     -- joined channels, in order
local registered = false
local dirty, inputDirty = true, true
local buf, history, hpos = "", {}, nil

local NICKCOLORS = { T.cyan, T.green, T.magenta, T.blue, T.yellow }
local function nickColor(n)
  local h = 0
  for c in n:gmatch(".") do h = (h * 31 + c:byte()) % 997 end
  return NICKCOLORS[h % #NICKCOLORS + 1]
end

local function add(parts)
  lines[#lines + 1] = { time = clock.date("%H:%M"), parts = parts }
  if #lines > MAXLINES then table.remove(lines, 1) end
  if scroll > 0 then scroll = scroll + 1 end -- keep looking at the same place
  dirty = true
end
local function info(text, colour) add({ { "-- " .. text, colour or T.muted } }) end

-- A message as screen rows of at most w cells: { { text, colour }, ... } each.
local function wrap(msg, w)
  local rows, row, used = {}, {}, 0
  local function put(text, colour)
    for ch in text:gmatch(utf8 and utf8.charpattern or ".") do
      if used >= w then rows[#rows + 1] = row; row, used = { { "      ", T.fg } }, 6 end
      local last = row[#row]
      if last and last[2] == colour then last[1] = last[1] .. ch else row[#row + 1] = { ch, colour } end
      used = used + 1
    end
  end
  put(msg.time .. " ", T.dim)
  for _, p in ipairs(msg.parts) do put(p[1], p[2]) end
  rows[#rows + 1] = row
  return rows
end

local function drawInput()
  local W, H = term.size()
  local prompt = "[" .. (target or "-") .. "] "
  local room = W - 2 - term.ulen(prompt)
  local shown = buf
  if term.ulen(shown) > room then shown = term.usub(shown, -room) end
  term.setCursor(1, H)
  term.cwrite(T.accent, prompt)
  term.cwrite(T.fg, shown)
  term.cwrite(T.muted, "_")
  term.clearLine()
  inputDirty = false
end

local function draw()
  local W, H = term.size()
  term.setCursor(1, 1)
  local status = (" %s  %s  %s%s"):format(server, target or "(no channel)", me, scroll > 0 and "  [scrolled]" or "")
  term.cwrite(T.accent, term.usub(status, 1, W))
  term.clearLine()
  local area = H - 2
  local rows = {}
  for n = #lines, 1, -1 do
    local r = wrap(lines[n], W - 1)
    for j = #r, 1, -1 do table.insert(rows, 1, r[j]) end
    if #rows >= area + scroll then break end
  end
  scroll = math.max(0, math.min(scroll, #rows - area))
  local first = math.max(1, #rows - area - scroll + 1)
  for y = 2, H - 1 do
    term.setCursor(1, y)
    local row = rows[first + y - 2]
    if row then for _, p in ipairs(row) do term.cwrite(p[2], p[1]) end end
    term.clearLine()
  end
  dirty = false
  drawInput()
end

-- ---- what the server says ---------------------------------------------------------------
-- prefix, COMMAND, params (the last one may contain spaces)
local function parse(line)
  local prefix, rest = line:match("^:(%S+)%s+(.*)$")
  if not prefix then rest = line end
  local trailing
  if rest:sub(1, 1) == ":" then trailing, rest = rest:sub(2), ""
  else
    local at = rest:find(" :", 1, true)
    if at then trailing, rest = rest:sub(at + 2), rest:sub(1, at - 1) end
  end
  local params = {}
  for w in rest:gmatch("%S+") do params[#params + 1] = w end
  local cmd = table.remove(params, 1)
  if trailing then params[#params + 1] = trailing end
  return prefix, cmd and cmd:upper(), params
end

local function nickOf(prefix) return prefix and prefix:match("^([^!@]+)") or "?" end
local function isChannel(s) return s and (s:sub(1, 1) == "#" or s:sub(1, 1) == "&") end

local function joined(ch)
  for _, c in ipairs(channels) do if c:lower() == ch:lower() then return true end end
end
local function forget(ch)
  for n, c in ipairs(channels) do if c:lower() == ch:lower() then table.remove(channels, n); break end end
  if target and target:lower() == ch:lower() then target = channels[#channels] end
end

local closed = false
local function handle(line)
  local prefix, cmd, p = parse(line)
  local who = nickOf(prefix)
  if cmd == "PING" then
    send("PONG :" .. (p[1] or ""))
  elseif cmd == "001" then
    registered, me = true, p[1] or me
    info("connected as " .. me, T.green)
    for _, ch in ipairs(autojoin) do send("JOIN " .. ch) end
  elseif cmd == "433" and not registered then
    me = me .. "_"
    info("nick in use, trying " .. me, T.yellow)
    send("NICK " .. me)
  elseif cmd == "PRIVMSG" or cmd == "NOTICE" then
    local to, text = p[1] or "", p[2] or ""
    local ctcp = text:match("^\1(.-)\1?$")
    if ctcp then
      local what, rest = ctcp:match("^(%S+)%s?(.*)$")
      if what == "ACTION" then
        add({ { (isChannel(to) and to ~= target) and (to .. " ") or "", T.dim }, { "* " .. who .. " " .. rest, nickColor(who) } })
      elseif what == "VERSION" and cmd == "PRIVMSG" then
        send("NOTICE " .. who .. " :\1VERSION ByteOS irc 1.0 (" .. tostring(_G._OSVERSION or "ByteOS") .. ")\1")
      end
      return
    end
    local mention = text:lower():find(me:lower(), 1, true) ~= nil
    local textColour = mention and T.yellow or T.fg
    if cmd == "NOTICE" then
      add({ { "-" .. who .. "- ", T.magenta }, { text, textColour } })
    elseif isChannel(to) then
      add({ { to ~= target and (to .. " ") or "", T.dim }, { "<" .. who .. "> ", nickColor(who) }, { text, textColour } })
    else
      add({ { "*" .. who .. "* ", nickColor(who) }, { text, T.yellow } })
    end
  elseif cmd == "JOIN" then
    local ch = p[1] or ""
    if who == me then
      if not joined(ch) then channels[#channels + 1] = ch end
      target = ch
      info("you joined " .. ch, T.green)
    else
      info(who .. " joined " .. ch)
    end
  elseif cmd == "PART" then
    if who == me then forget(p[1] or "") end
    info(who .. " left " .. (p[1] or "") .. (p[2] and (" (" .. p[2] .. ")") or ""))
  elseif cmd == "KICK" then
    if p[2] == me then forget(p[1] or "") end
    info(who .. " kicked " .. (p[2] or "?") .. " from " .. (p[1] or "") .. (p[3] and (" (" .. p[3] .. ")") or ""), T.yellow)
  elseif cmd == "QUIT" then
    info(who .. " quit" .. (p[1] and (" (" .. p[1] .. ")") or ""))
  elseif cmd == "NICK" then
    if who == me then me = p[1] or me end
    info(who .. " is now " .. (p[1] or "?"))
  elseif cmd == "332" then
    info("topic of " .. (p[2] or "") .. ": " .. (p[3] or ""), T.cyan)
  elseif cmd == "TOPIC" then
    info(who .. " set the topic of " .. (p[1] or "") .. ": " .. (p[2] or ""), T.cyan)
  elseif cmd == "353" then
    info("in " .. (p[3] or "") .. ": " .. (p[4] or ""))
  elseif cmd == "ERROR" then
    info("server: " .. (p[1] or "error"), T.red)
    closed = true
  elseif cmd and cmd:match("^%d%d%d$") then
    -- the rest of the numeric replies: their text, unless it is just noise
    local text = p[#p]
    if text and #p > 1 and cmd ~= "366" and cmd ~= "315" and cmd ~= "318" then
      info(text, cmd:sub(1, 1) == "4" and T.red or nil)
    end
  end
end

-- ---- what you type ------------------------------------------------------------------------
local quitting
local function say(to, text)
  -- IRC lines end at 512 bytes: send long text in pieces
  while #text > 0 do
    -- cut before a character, not inside one (UTF-8)
    local cut = math.min(#text, 400)
    while cut > 1 and cut < #text and text:byte(cut + 1) & 0xC0 == 0x80 do cut = cut - 1 end
    local piece = text:sub(1, cut)
    text = text:sub(cut + 1)
    send("PRIVMSG " .. to .. " :" .. piece)
    if isChannel(to) then
      add({ { to ~= target and (to .. " ") or "", T.dim }, { "<" .. me .. "> ", T.bright }, { piece, T.fg } })
    else
      add({ { "-> *" .. to .. "* ", T.bright }, { piece, T.fg } })
    end
  end
end

local COMMANDS = {}
function COMMANDS.join(a)
  local ch = a:match("^(%S+)")
  if not ch then return info("usage: /join #channel") end
  if not isChannel(ch) then ch = "#" .. ch end
  if joined(ch) then target = ch; dirty = true else send("JOIN " .. ch .. a:match("^%S+(.*)$")) end
end
function COMMANDS.part(a)
  local ch, msg = a:match("^(%S*)%s*(.*)$")
  if not isChannel(ch) then ch, msg = target, a end
  if not ch then return info("not in a channel") end
  send("PART " .. ch .. (msg ~= "" and (" :" .. msg) or ""))
end
function COMMANDS.msg(a)
  local to, text = a:match("^(%S+)%s+(.+)$")
  if not to then return info("usage: /msg NICK TEXT") end
  say(to, text)
end
function COMMANDS.query(a)
  local to = a:match("^(%S+)")
  if not to then return info("usage: /query NICK") end
  target = to; dirty = true
  info("talking to " .. to)
end
function COMMANDS.me(a)
  if not target then return info("join a channel first: /join #channel") end
  send("PRIVMSG " .. target .. " :\1ACTION " .. a .. "\1")
  add({ { "* " .. me .. " " .. a, T.bright } })
end
function COMMANDS.nick(a)
  local n = a:match("^(%S+)")
  if not n then return info("usage: /nick NEW") end
  send("NICK " .. n)
end
function COMMANDS.names(a)
  local ch = a:match("^(%S+)") or target
  if not ch then return info("not in a channel") end
  send("NAMES " .. ch)
end
function COMMANDS.topic(a)
  if not target then return info("not in a channel") end
  send("TOPIC " .. target .. (a ~= "" and (" :" .. a) or ""))
end
function COMMANDS.quote(a) if a ~= "" then send(a) end end
COMMANDS.raw = COMMANDS.quote
function COMMANDS.clear() lines = {}; scroll = 0; dirty = true end
function COMMANDS.quit(a) quitting = a ~= "" and a or "ByteOS" end
function COMMANDS.help()
  info("/join #chan  /part  /query NICK  /msg NICK TEXT  /me TEXT  /nick NEW  /names  /topic  /quote LINE  /clear  /quit")
end

local function submit(line)
  if line == "" then return end
  if history[#history] ~= line then history[#history + 1] = line end
  local name, rest = line:match("^/(%S+)%s*(.*)$")
  if name and line:sub(1, 2) ~= "//" then
    local fn = COMMANDS[name:lower()]
    if fn then fn(rest) else info("unknown command /" .. name .. " (/help lists them)") end
  elseif not target then
    info("join a channel first: /join #channel")
  else
    say(target, (line:gsub("^//", "/")))
  end
end

-- ---- the loop ------------------------------------------------------------------------------
send("NICK " .. me)
send("USER " .. me .. " 0 * :ByteOS user")
term.clear()
info(("connected to %s:%d, signing in ..."):format(server, port))

local CHAR = unicode and unicode.char or utf8.char
local received, ctrl = "", false
local ok, err = pcall(function()
  while not quitting and not closed do
    local okr, data = pcall(sock.read, 4096)
    if not okr or data == nil then
      info("the connection was closed" .. (okr and "" or (": " .. tostring(data))), T.red)
      closed = true
      break
    end
    if #data > 0 then
      received = received .. data
      for line in received:gmatch("([^\r\n]*)\r?\n") do
        if line ~= "" then handle(line) end
      end
      received = received:match("[^\n]*$")
    end
    if dirty then draw() elseif inputDirty then drawInput() end
    local ev, _, ch, code = k.event.pull(#data > 0 and 0 or 0.1)
    local _, H = term.size()
    if ev == "key_up" and (code == 29 or code == 157) then ctrl = false
    elseif ev == "clipboard" then buf = buf .. (ch or ""):match("^[^\r\n]*"); inputDirty = true
    elseif ev == "key_down" then
      if code == 29 or code == 157 then ctrl = true
      elseif code == 28 or code == 156 then
        local line = buf
        buf, hpos, inputDirty = "", nil, true
        submit(line)
      elseif code == 14 then buf = term.usub(buf, 1, -2); inputDirty = true
      elseif code == 200 or code == 208 then
        if #history > 0 then
          hpos = math.max(1, math.min(#history + 1, (hpos or #history + 1) + (code == 200 and -1 or 1)))
          buf = history[hpos] or ""
          inputDirty = true
        end
      elseif code == 201 then scroll = scroll + math.max(1, (H - 2) // 2); dirty = true
      elseif code == 209 then scroll = math.max(0, scroll - math.max(1, (H - 2) // 2)); dirty = true
      elseif ctrl and code == 38 then dirty = true -- Ctrl+L: draw everything again
      elseif ctrl and code == 32 then quitting = "ByteOS" -- Ctrl+D
      elseif not ctrl and ch and ch >= 32 and ch ~= 127 then buf = buf .. CHAR(math.floor(ch)); inputDirty = true
      end
    end
  end
end)
if not ok and err ~= "interrupted" then pcall(sock.close); error(err, 0) end
if not closed then send("QUIT :" .. (quitting or "ByteOS")) end
pcall(sock.close)
term.clear()
term.write("irc: disconnected from " .. server .. "\n")
return 0
