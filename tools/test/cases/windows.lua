-- Windows: extra terminals (lib/tty.lua) with shells running in them,
-- keys and Ctrl+C handed on with kernel.tty. A window manager (a package)
-- gives each one a surface of its own; here a band of the fake screen.
users()
local tty = require("tty")
local screen = term.console.gpu

-- rows top..top+h-1 of the screen, w wide, as a GPU of their own
local function band(top, w, h)
  local g = setmetatable({}, { __index = screen })
  function g.getResolution() return w, h end
  function g.setWidth(nw) w = nw end
  function g.set(x, y, s) if y >= 1 and y <= h then return screen.set(x, top + y - 1, s) end end
  function g.fill(x, y, fw, fh, ch) return screen.fill(x, top + y - 1, math.min(fw, w - x + 1), math.min(fh, h - y + 1), ch) end
  function g.copy(x, y, cw, ch, tx, ty) return screen.copy(x, top + y - 1, cw, ch, tx, ty) end
  function g.get(x, y) return screen.get(x, top + y - 1) end
  function g.line(y)
    local t = {}
    for x = 1, w do t[x] = (screen.get(x, top + y - 1)) end
    return table.concat(t)
  end
  return g
end

local function key(t, ch, code)
  kernel.tty.input(t, "key_down", "kb", ch, code)
  kernel.tty.input(t, "key_up", "kb", ch, code)
end
local function type(t, text)
  for c in text:gmatch(".") do
    if c == "\n" then key(t, 13, 28) else key(t, c:byte(), 0) end
  end
end
local function shows(s, text)
  local _, h = s.getResolution()
  for y = 1, h do if s.line(y):find(text, 1, true) then return true end end
  return false
end
local function window(w, h)
  local s = band(120, w, h)
  local t = tty.new(s)
  local pid = kernel.process.spawn(function() shell.loop() end, { name = "window", tty = t })
  kernel.event.pull(0) -- its first turn: up to the prompt
  return s, t, pid
end

test("a terminal on its own surface wraps and scrolls there", function()
  local g = band(150, 10, 3)
  local t = tty.new(g)
  t.write("0123456789abc\nx\ny")
  eq(g.line(1), "abc       "); eq(g.line(3), "y         ")
  eq(screen.get(1, 153), " ", "nothing below the surface")
end)

test("a shell in a window gets the keys handed to it", function()
  local s, t, pid = window(40, 10)
  ok(shows(s, "root@byteos"), "the prompt is in the window")
  type(t, "echo hello from the window\n")
  ok(shows(s, "hello from the window"), "the output is in the window")
  type(t, "cd /etc; nosuchcommand\n")
  ok(shows(s, "[127]"), "the window's prompt shows its status")
  eq(shell.status, 0, "the screen's $status is its own")
  eq(_G.PWD, "/", "the screen's directory is its own")
  type(t, "pwd > /tmp/wpwd\n")
  eq(file("/tmp/wpwd"), "/etc\n")
  type(t, "exit\n")
  eq(kernel.process.info(pid).state, "done")
end)

test("Ctrl+C stops the program in the window only", function()
  local s, t, pid = window(40, 10)
  type(t, "sleep 100\n")
  eq(kernel.process.info(pid).state, "running")
  kernel.tty.input(t, "key_down", "kb", 0, 29)  -- Ctrl
  kernel.tty.input(t, "key_down", "kb", 99, 46) -- C
  kernel.tty.input(t, "key_up", "kb", 0, 29)
  ok(shows(s, "^C"), "^C in the window")
  type(t, "echo $status > /tmp/wst\n")
  eq(file("/tmp/wst"), "130\n")
  kernel.tty.hangup(t)
  eq(kernel.process.info(pid).state, "killed")
end)

test("only its user (or root) types into a window", function()
  local _, t, pid = window(40, 5)
  as("bob", function()
    local done, err = kernel.tty.input(t, "key_down", "kb", 97, 0)
    ok(not done, "bob is refused"); has(tostring(err), "denied")
  end)
  kernel.tty.hangup(t)
  eq(kernel.process.info(pid).state, "killed")
end)

test("a line being typed follows when its window gets wider", function()
  local s = band(130, 12, 4)
  local t = tty.new(s)
  local pid = kernel.process.spawn(function() shell.loop() end, { name = "window", tty = t })
  kernel.event.pull(0)
  s.fill(1, 1, 60, 4, " "); s.setWidth(60); t.resize(0)    -- the window manager makes it wider
  type(t, "echo hello wide world")
  ok(shows(s, "echo hello wide world"), "the whole line on one row:\n" .. s.line(1) .. "\n" .. s.line(2))
  kernel.tty.hangup(t)
  eq(kernel.process.info(pid).state, "killed")
end)

test("sudo in a window stays root while the command waits (sudo pacman)", function()
  -- waits like a download does, then writes where only root may
  put("/usr/bin/slowwrite.lua", 'k.event.pull(0.05)\nlocal ok = fs.writeAll("/etc/sudotest", k.user() .. "\\n")\nreturn ok and 0 or 1\n')
  os.remove(ROOT .. "/etc/sudotest")
  local s = band(140, 60, 8)
  local t = tty.new(s)
  local pid
  as("alice", function()
    pid = kernel.process.spawn(function() shell.loop() end, { name = "alice's window", tty = t })
  end)
  kernel.event.pull(0)
  type(t, "sudo slowwrite\n")
  ok(shows(s, "password for alice"), "sudo asks in the window")
  type(t, "alicepw\n")
  for _ = 1, 20 do kernel.event.pull(0.01) end
  eq(file("/etc/sudotest"), "root\n", "still root after waiting")
  type(t, "whoami > /tmp/who\n")
  eq(file("/tmp/who"), "alice\n", "alice again after sudo")
  -- a root command in alice's window: she still types into it and closes it
  type(t, "sudo sleep 100\n")
  as("alice", function()
    ok(kernel.tty.input(t, "key_down", "kb", 97, 0), "alice types into her window")
    ok(kernel.tty.hangup(t), "alice closes her window")
  end)
  eq(kernel.process.info(pid).state, "killed")
end)
