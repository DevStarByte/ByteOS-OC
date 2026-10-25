-- The packages on the packages branch: built with tools/mkrepo.lua,
-- installed with pacman and tried out on fake hardware (see
-- tools/test/pkgrepo.lua for where the sources come from).
users()
local function q(p) return "'" .. p:gsub("'", "'\\''") .. "'" end
local P = dofile(REPO .. "/tools/test/pkgrepo.lua")
if not P then return end
local ME = "5e1f0000-0000-0000-0000-000000000001"
network({}, ME)

test("every new package installs", function()
  local out = run(P .. "-Sy lshw redstone power timers rsh netfs")
  lacks(out, "error")
  for _, n in ipairs({ "lshw", "redstone", "power", "timers", "rsh", "netfs" }) do
    ok(file("/var/lib/pacman/local/" .. n .. "/desc"), n .. " installed")
  end
  has(file("/etc/systemd/enabled"), "timerd"); has(file("/etc/systemd/enabled"), "rshd")
  has(file("/etc/systemd/enabled"), "netfsd")
end)

test("lshw lists the devices", function()
  machine({ devices = {
    ["cpu00000-1"] = { class = "processor", description = "CPU", product = "FlexiArch Processor", clock = "1500" },
    ["mem00000-1"] = { class = "memory", description = "Memory bank", product = "Tier 2", size = "1048576" },
  } })
  local out = run("lshw")
  has(out, "*-processor"); has(out, "FlexiArch Processor"); has(out, "clock:")
  has(out, "*-filesystem")  -- no details from OpenComputers: still listed
  out = run("lshw -short memory")
  has(out, "mem00000"); has(out, "Tier 2"); lacks(out, "processor")
  has(run("lshw nothing"), "no nothing found")
end)

test("redstone reads and sets, root only", function()
  has(run("redstone"), "no redstone card")
  local outs, bundled = {}, {}
  plug("redstone", "rs000000-1", {
    getInput = function(s) return s == 1 and 15 or 0 end,
    getOutput = function(s) return outs[s] or 0 end,
    setOutput = function(s, v) outs[s] = v; return 0 end,
    getBundledInput = function(s, c) return c == 14 and 255 or 0 end,
    getBundledOutput = function(s, c) return bundled[s .. ":" .. c] or 0 end,
    setBundledOutput = function(s, c, v) bundled[s .. ":" .. c] = v end,
  })
  has(run("redstone"), "top         15      0")
  eq(run("redstone get top"), "15\n")
  run("redstone set front 7"); eq(outs[3], 7)
  run("redstone bundled back red 200"); eq(bundled["2:14"], 200)
  has(run("redstone bundled left"), "red          255      0")
  has(run("redstone set sideways 1"), "unknown side")
  as("bob", function() has(run("redstone set top 1"), "only root") end)
  undisk("rs000000-1")
end)

test("power shows energy and how long it lasts", function()
  machine({ energy = 2500, maxEnergy = 10000 })
  local out = run("power")
  has(out, "2500 / 10000 (25%)"); has(out, "Gaining"); has(out, "Full in")
end)

test("timers: a timer starts its service", function()
  put("/etc/systemd/system/tick.service", "[Unit]\nDescription=tick\n\n[Service]\nExecStart=echo tock\n")
  put("/etc/systemd/system/tick.timer", "[Timer]\nOnBootSec=0\nOnUnitActiveSec=1h\n")
  put("/etc/systemd/system/bad.timer", "[Timer]\nOnCalendar=sometimes\n")
  local out = run("timers")
  has(out, "tick             no"); has(out, "bad OnCalendar=sometimes")
  has(run("timers enable bad"), "bad OnCalendar")
  has(run("timers enable tick"), "Enabled tick.timer")
  local timers = require("timers")
  timers.tick()
  ok(timers.state.tick and timers.state.tick.last, "tick ran")
  for _ = 1, 20 do kernel.event.pull(0.01) end
  has(run("journalctl -u tick"), "tock")
  out = run("timers")
  has(out, "in 59min"); has(out, "tick.service")
  eq(timers.span("1h 30min"), 5400)
  as("bob", function() has(run("timers disable tick"), "only root") end)
  run("timers disable tick")
  has(run("timers"), "tick             no")
end)

test("timers: calendar times", function()
  put("/etc/systemd/system/cal.timer", "[Timer]\nOnCalendar=*:00/15\n")
  put("/etc/systemd/system/cal.service", "[Service]\nExecStart=true\n")
  run("timers enable cal")
  local timers = require("timers")
  for _, u in ipairs(timers.load()) do
    if u.name == "cal" then ok(timers.nextRun(u) <= 15 * 60, "within a quarter hour") end
  end
  run("timers disable cal")
end)

test("timers: world time skips minutes, the clocks going back repeats them", function()
  put("/etc/systemd/system/cal2.timer", "[Timer]\nOnCalendar=14:30\n")
  put("/etc/systemd/system/cal2.service", "[Service]\nExecStart=true\n")
  run("timers enable cal2")
  local timers, real = require("timers"), package.loaded.clock
  local T, synced, off = 14 * 3600 + 25 * 60, false, function() return 0 end
  package.loaded.clock = setmetatable({ now = function() return T, synced end,
    zone = function(t) return "X", off(t) end }, { __index = real })
  local okRun, err = pcall(function()
    -- without a synced clock a tick 5 s after the last is 6 world minutes on
    for _ = 1, 4 do timers.tick(); T = T + 360 end
    eq(timers.state.cal2.lastClock, 14 * 3600 + 31 * 60, "14:30 fell between two ticks")
    -- 02:00-03:00 twice (UTC+2, then UTC+1 from 01:00 UTC): 02:30 runs once
    put("/etc/systemd/system/cal2.timer", "[Timer]\nOnCalendar=02:30\n")
    timers.state.cal2, synced = nil, true
    local switch = 86400 + 3600
    off = function(t) return t < switch and 7200 or 3600 end
    local starts, last = 0, nil
    for t = 86400 - 3600, 86400 + 3 * 3600, 30 do
      T = t; timers.tick()
      local st = timers.state.cal2
      if st and st.lastClock ~= last then starts, last = starts + 1, st.lastClock end
    end
    eq(starts, 1, "one start in the night the clocks go back")
  end)
  package.loaded.clock = real
  run("timers disable cal2")
  if not okRun then error(err, 0) end
end)

test("rsh runs commands as the user, over the network", function()
  run("systemctl start rshd")
  for _ = 1, 5 do kernel.event.pull(0.01) end
  answers({ "alicepw" })
  local out, rc = run("rsh alice@" .. ME .. " whoami")
  has(out, "alice"); eq(rc, 0)
  -- the time limit is not cut short by the network messages meanwhile
  answers({ "alicepw" })
  out, rc = run("rsh alice@" .. ME .. " sleep 0.3")
  lacks(out, "stopped after"); eq(rc, 0, out)
  answers({ "wrong" })
  out, rc = run("rsh alice@" .. ME .. " whoami")
  has(out, "Permission denied"); eq(rc, 1)
  eq(_G.PWD, "/", "a remote cd does not move this shell")
end)

test("netfs shares a folder, read-only and read-write", function()
  put("/srv/share/hello.txt", "hi from the share\n")
  os.execute("mkdir -p " .. q(ROOT .. "/srv/share/sub"))
  put("/etc/netfs.conf", "pub /srv/share ro\ndrop /srv/drop rw\n")
  os.execute("mkdir -p " .. q(ROOT .. "/srv/drop"))
  run("systemctl start netfsd")
  for _ = 1, 5 do kernel.event.pull(0.01) end
  local out = run("netfs shares " .. ME)
  has(out, "pub              ro"); has(out, "drop             rw")
  has(run("netfs mount " .. ME .. ":pub /mnt/pub"), "Mounted")
  has(run("netfs mount " .. ME .. ":nope /mnt/x"), "no share nope")
  out = run("ls /mnt/pub")
  has(out, "hello.txt"); has(out, "sub")
  eq(run("cat /mnt/pub/hello.txt"), "hi from the share\n")
  -- the kernel resolves .. itself; a request with .. stays inside the share
  local net = require("net")
  local _, _, okRead, data = net.request(ME, "netfs", 3, "pub", "read", "/../../etc/hostname", 0, 100)
  ok(not okRead, "cannot climb out of the share: " .. tostring(data))
  put("/etc/netfs.conf", "all / ro\n")
  _, _, okRead, data = net.request(ME, "netfs", 3, "all", "read", "/etc/shadow", 0, 100)
  ok(not okRead, "a share of / still hides /etc/shadow")
  -- \\ is a / to the kernel; a link leads nowhere outside the share either
  put("/etc/netfs.conf", "pub /srv/share ro\ndrop /srv/drop rw\n")
  _, _, okRead, data = net.request(ME, "netfs", 3, "pub", "read", "..\\..\\etc\\hostname", 0, 100)
  ok(not okRead, "a path with \\ stays inside: " .. tostring(data))
  run("ln -s /etc /srv/share/out")
  _, _, okRead, data = net.request(ME, "netfs", 3, "pub", "read", "/out/hostname", 0, 100)
  ok(not okRead, "a link out of the share: " .. tostring(data))
  put("/etc/motd.bak", "keep\n")
  run("ln -s /etc/motd.bak /srv/drop/m")
  local _, _, okWrite = net.request(ME, "netfs", 3, "drop", "write", "/m", "overwritten")
  ok(not okWrite); eq(file("/etc/motd.bak"), "keep\n")
  run("ln -s hello.txt /srv/share/in")
  _, _, okRead, data = net.request(ME, "netfs", 3, "pub", "read", "/in", 0, 100)
  ok(okRead); eq(data, "hi from the share\n", "a link inside the share works")
  run("rm /srv/share/out /srv/share/in /srv/drop/m /etc/motd.bak")
  put("/etc/netfs.conf", "pub /srv/share ro\ndrop /srv/drop rw\n")
  has(run("echo nope > /mnt/pub/new.txt"), "")
  ok(not file("/srv/share/new.txt"), "read-only share not written")
  run("netfs mount " .. ME .. ":drop /mnt/drop")
  run("echo saved > /mnt/drop/note.txt")
  eq(file("/srv/drop/note.txt"), "saved\n")
  run("rm /mnt/drop/note.txt")
  ok(not file("/srv/drop/note.txt"), "removed on the server")
  has(run("netfs"), "/mnt/pub")
  has(run("netfs umount /mnt/pub"), "Unmounted")
  lacks(run("netfs"), "/mnt/pub")
end)

test("btop shows the system and stops a process", function()
  lacks(run(P .. "-S btop"), "error")
  machine({ energy = 7500, maxEnergy = 10000 })
  local out = run("btop -1")
  has(out, "memory"); has(out, "of 192 KiB used"); has(out, "7500 of 10000 (75%)")
  has(out, "disks"); has(out, "/mnt/drop"); has(out, "5e1f0000-"); has(out, "card 5e1f0000 wired")
  has(out, "services"); has(out, "processes"); has(out, "init")
  run("sleep 1000 &")
  local victim
  for _, p in ipairs(kernel.process.list()) do victim = p end
  has(victim.name, "sleep")
  -- PageDown picks the last process, k stops it, q quits
  signals({ { "key_down", "kb", 0, 209 }, { "key_down", "kb", 107, 37 }, { "key_down", "kb", 113, 16 } })
  run("btop")
  eq(kernel.process.info(victim.pid).state, "killed")
end)

test("removing the packages stops their services", function()
  lacks(run(P .. "-R rsh netfs timers"), "error")
  lacks(file("/etc/systemd/enabled") or "", "rshd")
  lacks(file("/etc/systemd/enabled") or "", "timerd")
end)

-- ---- hyprbyte: a whole session driven by key presses ------------------------------
local ALT, SHIFT = 56, 42
local function down(ch, code) return { "key_down", "kb", ch, code } end
local function up(ch, code) return { "key_up", "kb", ch, code } end
local function typed(text, into)
  for c in text:gmatch(".") do
    if c == "\n" then into[#into + 1] = down(13, 28); into[#into + 1] = up(13, 28)
    else into[#into + 1] = down(c:byte(), 0); into[#into + 1] = up(c:byte(), 0) end
  end
end
local function mod(code, ch, into, shift)
  into[#into + 1] = down(0, ALT)
  if shift then into[#into + 1] = down(0, SHIFT) end
  into[#into + 1] = down(ch or 0, code); into[#into + 1] = up(ch or 0, code)
  if shift then into[#into + 1] = up(0, SHIFT) end
  into[#into + 1] = up(0, ALT)
end
local function row(y)
  local t = {}
  for x = 1, 80 do t[x] = (term.console.gpu.get(x, y)) end
  return table.concat(t)
end
local function rows(from, to)
  local t = {}
  for y = from, to do t[#t + 1] = row(y) end
  return table.concat(t, "\n")
end

test("hyprbyte tiles terminals and hands the keys to the one in focus", function()
  lacks(run(P .. "-S hyprbyte"), "error")
  ok(file("/usr/bin/start-hyprbyte.lua"), "start-hyprbyte starts it")
  eq(file("/usr/share/sessions/hyprbyte.session"), nil, "not a login session")
  local seq, shot = {}, nil
  typed("echo one > /tmp/w1\n", seq)              -- the first terminal
  mod(28, 13, seq)                                 -- Alt+Enter: a second one
  typed("echo two > /tmp/w2; hyprctl clients > /tmp/clients\n", seq)
  seq[#seq + 1] = function() shot = rows(1, 200) end
  mod(203, 0, seq)                                 -- Alt+Left: back to the first
  typed("hyprctl activewindow > /tmp/active\n", seq)
  mod(3, 50, seq, true)                            -- Alt+Shift+2: send it to workspace 2
  typed("hyprctl workspaces > /tmp/spaces\n", seq)
  mod(18, 69, seq, true)                           -- Alt+Shift+E: quit
  signals(seq)
  local _, rc = run("start-hyprbyte --no-animations")
  eq(rc, 0)
  eq(file("/tmp/w1"), "one\n"); eq(file("/tmp/w2"), "two\n")
  has(file("/tmp/clients"), "Window 1"); has(file("/tmp/clients"), "Window 2")
  has(file("/tmp/active"), "Window 1")
  has(file("/tmp/spaces"), "workspace 1 (active): 1 window"); has(file("/tmp/spaces"), "workspace 2: 1 window")
  -- the screen while two windows were open: no bar of its own (that is
  -- quickshell's job), the first window starts at the top
  ok(shot:find("^╭─ / ─"), "no built-in bar:\n" .. shot:sub(1, 160)); has(shot, "two")
  -- the test screen is 80 x 200, tall: dwindle puts the second one below;
  -- the titles are what the shells say: their directory between commands
  eq(select(2, shot:gsub("╭─ / ─", "")), 2, "two frames titled /")
  ok(shot:find("╯\n╭─ / ─", 1, true), "one below the other")
  for _, p in ipairs(kernel.process.list()) do lacks(p.name, "hyprbyte:", "every window closed") end
  eq(package.loaded["hyprbyte.state"], nil)
  has(run("hyprctl"), "not running")
end)

test("Ctrl+C in a window stops its program, not Hyprbyte", function()
  local seq = {}
  typed("sleep 100\n", seq)
  seq[#seq + 1] = down(0, 29); seq[#seq + 1] = down(99, 46); seq[#seq + 1] = up(99, 46); seq[#seq + 1] = up(0, 29)
  typed("echo $status > /tmp/hst\n", seq)
  mod(16, 113, seq)                                -- Alt+Q closes the window
  mod(18, 69, seq, true)
  signals(seq)
  local _, rc = run("hyprbyte --no-animations")
  eq(rc, 0); eq(file("/tmp/hst"), "130\n")
end)

test("quickshell puts its panels into Hyprbyte and follows its file", function()
  lacks(run(P .. "-S quickshell"), "error")
  put("/home/root/.config/hyprbyte.conf", "exec-once = quickshell\n")
  local SHELL = "/home/root/.config/quickshell/shell.lua"
  put(SHELL, [[return {
    PanelWindow { anchor = "top", Text { text = "hello from quickshell" }, Spacer {}, Workspaces {} },
    PanelWindow { anchor = "bottom", Command { cmd = "echo cmd output", interval = 100 }, Spacer {},
      Button { text = "run", onClick = function() hypr.clicked = true end } },
  }]])
  local seq, before, active, edited, broken = {}, nil, nil, nil, nil
  local function settle() for _ = 1, 4 do seq[#seq + 1] = { "noop" } end end
  local function wait(s) seq[#seq + 1] = function() local t = os.clock(); while os.clock() - t < s do end end end
  settle()
  seq[#seq + 1] = function() before = rows(1, 200) end
  seq[#seq + 1] = { "touch", "screen", 70, 1, 0, "player" }   -- workspace 2 in the top panel
  seq[#seq + 1] = { "touch", "screen", 78, 200, 0, "player" }  -- the button at the bottom
  settle()
  local clicked
  seq[#seq + 1] = function()
    active = package.loaded["hyprbyte.state"].active
    clicked = package.loaded["hyprbyte.state"].clicked
  end
  seq[#seq + 1] = function() put(SHELL, 'return PanelWindow { Text { text = "changed text" } }') end
  wait(2.3); settle()
  seq[#seq + 1] = function() edited = rows(1, 3) end
  seq[#seq + 1] = function() put(SHELL, "return {") end
  wait(2.3); settle()
  seq[#seq + 1] = function() broken = rows(1, 1) end
  mod(18, 69, seq, true)
  signals(seq)
  local _, rc = run("hyprbyte --no-animations")
  eq(rc, 0)
  ok(before:find("^ hello from quickshell"), "the top panel:\n" .. before:sub(1, 240))
  ok(before:match("\n╭"), "the windows start below it")
  has(before:sub(-200), "cmd output", "the bottom panel")
  eq(active, 2, "a click on 2 went to workspace 2")
  eq(clicked, true, "the button's onClick ran")
  ok(package.loaded["hyprbyte.state"] == nil, "Hyprbyte ended")
  has(edited, "changed text"); lacks(edited, "hello from quickshell")
  has(broken, "quickshell:")
  for _, p in ipairs(kernel.process.list()) do lacks(p.name, "quickshell", "stopped with Hyprbyte") end
end)

-- ---- the Hyprbyte ecosystem ---------------------------------------------------------
local function settle(seq, n) for _ = 1, n or 4 do seq[#seq + 1] = { "noop" } end end
local function spin(seq, s) seq[#seq + 1] = function() local t = os.clock(); while os.clock() - t < s do end end end

test("dunst shows notify-send and ByteNet messages; hyprpaper fills empty space", function()
  lacks(run(P .. "-S libnotify dunst rofi hyprlock hypridle hyprpaper"), "error")
  has(run("notify-send hi"), "no notification daemon")
  run("systemctl start netd")
  put("/home/root/.config/hyprbyte.conf", "exec-once = dunst\nexec-once = hyprpaper\n")
  local seq, s1, s2, s3 = {}, nil, nil, nil
  settle(seq)
  typed('notify-send -a test Hello "from the window"\n', seq)
  settle(seq)
  seq[#seq + 1] = function() s1 = rows(1, 12) end
  seq[#seq + 1] = { "modem_message", "modem000-test", "b0b00000-0000-0000-0000-000000000009", 4400, 3,
                    "bytenet", "msg", "id-1", "bob@box2", "dinner is ready" }
  settle(seq)
  seq[#seq + 1] = function() s2 = rows(1, 20) end
  typed("dunstctl history > /tmp/dh\n", seq)
  mod(3, 50, seq)                                  -- Alt+2: an empty workspace
  settle(seq)
  seq[#seq + 1] = function() s3 = rows(1, 200) end
  mod(18, 69, seq, true)
  signals(seq)
  local _, rc = run("hyprbyte --no-animations")
  eq(rc, 0)
  has(s1, "Hello"); has(s1, "from the window"); has(s1, " test ")
  has(s2, "Message from bob@box2"); has(s2, "│ dinner is ready"); lacks(s2, "bob@box2: dinner", "the body is the message alone")
  has(file("/tmp/dh"), "[test] Hello: from the window")
  has(s3, "B y t e O S"); has(s3, "·")
  lacks(s3, "root@byteos", "workspace 2 has no window")
end)

test("rofi finds and starts programs and switches windows", function()
  put("/home/root/.config/hyprbyte.conf", "")
  local seq, picking, layersAfterEsc, focusAfter = {}, nil, nil, nil
  settle(seq)
  mod(32, 100, seq); settle(seq)                   -- Alt+D: rofi
  typed("unam", seq); settle(seq, 2)
  seq[#seq + 1] = function() picking = rows(1, 200) end
  seq[#seq + 1] = down(13, 28); seq[#seq + 1] = up(13, 28); settle(seq)
  mod(32, 100, seq); settle(seq)
  typed("hyprctl clients > /tmp/rc\n", seq); settle(seq)
  mod(32, 100, seq); settle(seq)
  seq[#seq + 1] = down(0, 1); seq[#seq + 1] = up(0, 1); settle(seq)   -- Esc closes it
  seq[#seq + 1] = function()
    layersAfterEsc = 0
    for _, l in ipairs(package.loaded["hyprbyte.state"].layers) do if l.namespace == "rofi" then layersAfterEsc = layersAfterEsc + 1 end end
  end
  mod(28, 13, seq); settle(seq)                    -- a second terminal, in focus
  mod(17, 119, seq); settle(seq)                   -- Alt+W: the window list
  seq[#seq + 1] = down(13, 28); seq[#seq + 1] = up(13, 28); settle(seq) -- the first one
  seq[#seq + 1] = function() local s = package.loaded["hyprbyte.state"]; focusAfter = s.workspaces[1].focus end
  mod(18, 69, seq, true)
  signals(seq)
  run("hyprbyte --no-animations")
  has(picking, "❯ unam"); has(picking, " uname")
  has(file("/home/root/.cache/rofi.history"), "uname")
  has(file("/tmp/rc"), "Window 1")
  eq(layersAfterEsc, 0, "Esc closed rofi")
  eq(focusAfter, 1, "the window picked in rofi is in focus")
end)

test("hypridle locks the screen with hyprlock; only the password opens it", function()
  put("/home/root/.config/hyprbyte.conf", "exec-once = hypridle\n")
  put("/home/root/.config/hypr/hypridle.conf", "listener = 1, hyprlock\n")
  os.remove(ROOT .. "/tmp/leak")
  local seq, locked, wrong, open = {}, nil, nil, nil
  settle(seq)
  spin(seq, 1.3); settle(seq, 8)                   -- a second without input
  seq[#seq + 1] = function() locked = rows(1, 200) end
  typed("echo leak > /tmp/leak\n", seq); settle(seq)
  seq[#seq + 1] = function() wrong = rows(1, 200) end
  spin(seq, 2.3)
  typed("rootpw\n", seq); settle(seq)
  seq[#seq + 1] = function() open = rows(1, 200) end
  mod(18, 69, seq, true)
  signals(seq)
  run("hyprbyte --no-animations")
  has(locked, "Locked · root"); lacks(locked, "root@byteos", "the windows are hidden")
  has(wrong, "wrong password")
  ok(not file("/tmp/leak"), "nothing typed reached a window")
  has(open, "root@byteos"); lacks(open, "Locked")
  has(file("/var/log/messages"), "hyprlock: wrong password for root")
end)

test("a new window's shell starts at the window's size, also while it pops open", function()
  put("/home/root/.config/hyprbyte.conf", "")
  local seq, shot = {}, nil
  -- each animation frame waits 0.04 s and takes what is queued meanwhile:
  -- let real time pass in each of the two frames of an opening window
  spin(seq, 0.1); spin(seq, 0.1); settle(seq)      -- the first window
  mod(28, 13, seq)                                 -- a second one
  spin(seq, 0.1); spin(seq, 0.1); settle(seq, 8)
  seq[#seq + 1] = function() shot = rows(1, 200) end
  mod(18, 69, seq, true)
  signals(seq)
  run("hyprbyte")                                  -- animations on
  eq(select(2, shot:gsub("│root@byteos /# ", "")), 2, "both prompts on one line:\n" .. shot:sub(1, 800))
end)

test("nano edits like GNU nano", function()
  lacks(run(P .. "-S nano vim"), "error")
  keys({ "hello", "<enter>", "world", "<ctrl+o>", "<ctrl+x>" })
  answers({ "" })                                  -- File Name to Write: keep it
  local _, rc = run("nano /tmp/n.txt")
  eq(rc, 0)
  eq(file("/tmp/n.txt"), "hello\nworld\n")
  -- ^W search, ^K cut, ^U paste twice, ^X asks to save: Y, keep the name
  keys({ "<ctrl+w>", "X", "<ctrl+k>", "<ctrl+u>", "<ctrl+u>", "<ctrl+x>", "y" })
  answers({ "wor", "" })
  run("nano /tmp/n.txt")
  eq(file("/tmp/n.txt"), "Xworld\nXworld\nhello\n")
  -- ^X without changes just leaves; ^C (Location) does not stop nano
  keys({ "<ctrl+c>", "<ctrl+x>" })
  eq(select(2, run("nano /tmp/n.txt")), 0)
end)

test("vim edits like Vim: modes, operators, undo, :s and search", function()
  keys({ "i", "hello world", "<escape>", "o", "second line", "<escape>", "g", "g", "d", "w", ":" })
  answers({ "wq" })
  run("vim /tmp/v.txt")
  eq(file("/tmp/v.txt"), "world\nsecond line\n")

  put("/tmp/v.txt", "a\nb\nc\n")
  keys({ "y", "y", "p",            -- a a b c
         "G", "d", "d", "u",       -- dd the last line, undo it
         ":", ":",                 -- :%s/a/z/g, then :q is refused (unsaved)
         "g", "g", "/", "x",       -- /c, delete it
         ":" })                    -- :wq
  answers({ "%s/a/z/g", "q", "c", "wq" })
  run("vim /tmp/v.txt")
  eq(file("/tmp/v.txt"), "z\nz\nb\n\n")

  keys({ "3", "x", "Z", "Q" })     -- ZQ: quit without saving
  put("/tmp/v.txt", "abcdef\n")
  run("vim /tmp/v.txt")
  eq(file("/tmp/v.txt"), "abcdef\n")
end)

-- ---- the small ones: toys and games ----------------------------------------------

test("cowsay, lolcat, fortune, hello and tree", function()
  lacks(run(P .. "-S cowsay lolcat fortune hello tree"), "error")
  local out = run("cowsay moo moo")
  has(out, "< moo moo >"); has(out, "(oo)")
  has(run("lolcat hi"), "hi")
  ok(file("/usr/share/fortune/quotes.txt"):find(run("fortune"):match("^%s*(.-)%s*$"), 1, true), "a line of the quotes")
  has(run("hello"), "Greetings, root")
  put("/tmp/t/a/b.txt", "x"); put("/tmp/t/c.txt", "x")
  out = run("tree /tmp/t")
  has(out, "|-- a/"); has(out, "|   `-- b.txt"); has(out, "`-- c.txt"); has(out, "1 directories, 2 files")
  local _, rc = run("tree /tmp/nothing")
  eq(rc, 1)
  -- each one has a manual page
  for _, n in ipairs({ "cowsay", "lolcat", "fortune", "hello", "tree" }) do
    has(run("man " .. n), n .. " - ")
  end
end)

test("figlet draws with the Standard font like FIGlet", function()
  lacks(run(P .. "-S figlet"), "error")
  eq(run("figlet ByteOS"), table.concat({
    " ____        _        ___  ____",
    "| __ ) _   _| |_ ___ / _ \\/ ___|",
    "|  _ \\| | | | __/ _ \\ | | \\___ \\",
    "| |_) | |_| | ||  __/ |_| |___) |",
    "|____/ \\__, |\\__\\___|\\___/|____/",
    "       |___/", "" }, "\n"))
  -- words go on a new line when the screen is too narrow; -c centres
  local out = run("figlet -w 30 -c Hi there")
  has(out, "          | | | (_)\n"); has(out, "| __| '_ \\ / _ \\ '__/ _ \\")
  has(run("echo hi | figlet"), "| '_ \\| |")
  has(run("figlet -f nope x"), "no font /usr/share/figlet/nope.flf")
  has(run("man figlet"), "figlet - big letters")
end)

test("the games start and quit on q", function()
  lacks(run(P .. "-S 2048 snake cmatrix sl"), "error")
  local Q = { "key_down", "kb", 113, 16 }
  signals({ { "key_down", "kb", 0, 203 }, Q })    -- left, then q
  has(run("2048"), "2048: final score")
  signals({ Q, Q })                               -- q, and the key after GAME OVER
  has(run("snake"), "snake: final score 0")
  signals({ Q })
  eq(select(2, run("cmatrix")), 0)
  eq(select(2, run("sl")), 0)
  for _, n in ipairs({ "2048", "snake", "cmatrix", "sl" }) do has(run("man " .. n), n .. " - ") end
end)

-- tar (extra/tar): packing, listing, unpacking, ustar compatibility
local function sh(c) return os.execute(c) == true end

test("tar installs from extra", function()
  lacks(run(P .. "-S tar"), "error")
  ok(file("/usr/bin/tar.lua"), "tar is in /usr/bin")
end)

-- a member header as another tar might write it
local function header(name, kind, size)
  local function field(s, n) return s .. ("\0"):rep(n - #s) end
  local h = field(name, 100) .. "0000644\0" .. "0000000\0" .. "0000000\0" .. ("%011o\0"):format(size)
    .. "00000000000\0" .. "        " .. kind .. field("", 100) .. "ustar\0" .. "00" .. field("root", 32)
    .. field("root", 32) .. ("\0"):rep(16) .. field("", 155) .. ("\0"):rep(12)
  local sum = 0
  for i = 1, 512 do sum = sum + h:byte(i) end
  return h:sub(1, 148) .. ("%06o\0 "):format(sum) .. h:sub(157)
end

put("/tmp/src/a.txt", "hello\n")
put("/tmp/src/sub/b.txt", string.rep("0123456789", 300))
put("/tmp/src/sub/deep/c.txt", "")

test("tar: create, list, extract with directories and -C", function()
  local _, rc = run("tar -cf /tmp/x.tar -C /tmp src")
  eq(rc, 0)
  local data = file("/tmp/x.tar")
  eq(#data % 512, 0, "whole blocks")
  eq(data:sub(258, 262), "ustar", "ustar magic at offset 257")
  local sum = 0
  for i = 1, 512 do sum = sum + ((i >= 149 and i <= 156) and 32 or data:byte(i)) end
  eq(tonumber(data:sub(149, 154), 8), sum, "header checksum")
  eq(data:sub(1, 4), "src/")
  eq(data:sub(-1024), ("\0"):rep(1024), "two zero blocks at the end")
  eq(run("tar -tf /tmp/x.tar"), "src/\nsrc/a.txt\nsrc/sub/\nsrc/sub/b.txt\nsrc/sub/deep/\nsrc/sub/deep/c.txt\n")
  has(run("tar tvf /tmp/x.tar"), "-rw-rw-rw- root/root     3000 ", "files in /tmp are rw for everyone")
  run("mkdir /tmp/out")
  eq(run("tar xvf /tmp/x.tar -C /tmp/out"), "src/\nsrc/a.txt\nsrc/sub/\nsrc/sub/b.txt\nsrc/sub/deep/\nsrc/sub/deep/c.txt\n")
  eq(file("/tmp/out/src/a.txt"), "hello\n")
  eq(file("/tmp/out/src/sub/b.txt"), string.rep("0123456789", 300))
  eq(file("/tmp/out/src/sub/deep/c.txt"), "")
  local verbose = run("tar -cvf /tmp/y.tar -C /tmp/src a.txt")
  eq(verbose, "a.txt\n")
end)

test("tar: through a pipe, leading / and long names", function()
  eq(run("tar cf - -C /tmp src/sub/deep | tar tf -"), "src/sub/deep/\nsrc/sub/deep/c.txt\n")
  has(run("tar cf /tmp/abs.tar /tmp/src/a.txt"), "removing leading '/'")
  eq(run("tar tf /tmp/abs.tar"), "tmp/src/a.txt\n")
  run("mkdir /tmp/abs; cd /tmp/abs; tar xf /tmp/abs.tar; cd /")
  eq(file("/tmp/abs/tmp/src/a.txt"), "hello\n", "unpacked below the current directory")
  local long = "/tmp/" .. string.rep("d", 60) .. "/" .. string.rep("e", 60) .. "/f.txt"
  put(long, "deep")
  run("tar cf /tmp/long.tar -C /tmp " .. long:sub(6))
  run("mkdir /tmp/lo; tar xf /tmp/long.tar -C /tmp/lo")
  eq(file("/tmp/lo" .. long:sub(5)), "deep", "a name over 100 characters uses the prefix field")
  local err, rc = run("tar czf /tmp/z.tar /tmp/src")
  has(err, "tar -z needs the gzip package"); eq(rc, 2) -- gzip is not installed here (see pkg_compress)
end)

test("tar: members with .. are skipped, garbage is refused", function()
  put("/tmp/evil.tar", header("../evil.txt", "0", 4) .. "evil" .. ("\0"):rep(508)
    .. header("ok.txt", "0", 2) .. "ok" .. ("\0"):rep(510) .. ("\0"):rep(1024))
  run("mkdir /tmp/ev")
  local out, rc = run("tar xf /tmp/evil.tar -C /tmp/ev")
  has(out, "'..'"); eq(rc, 2)
  ok(not file("/tmp/evil.txt"), "nothing written outside")
  eq(file("/tmp/ev/ok.txt"), "ok", "the other members are unpacked")
  put("/tmp/junk.tar", string.rep("x", 1024))
  has(run("tar tf /tmp/junk.tar"), "does not look like a tar archive")
end)

test("tar: no writing through a link of the archive's own, no hard link out", function()
  local function member(name, kind, link, body)
    local h = header(name, kind, body and #body or 0)
    if link then
      h = h:sub(1, 157) .. link .. ("\0"):rep(100 - #link) .. h:sub(258)
      local sum = 0
      for i = 1, 512 do sum = sum + (i >= 149 and i <= 156 and 32 or h:byte(i)) end
      h = h:sub(1, 148) .. ("%06o\0 "):format(sum) .. h:sub(157)
    end
    return h .. (body and body .. ("\0"):rep((512 - #body % 512) % 512) or "")
  end
  put("/tmp/out/keep.txt", "keep\n")
  put("/tmp/sneaky.tar", member("lnk", "2", "/tmp/out") .. member("lnk/keep.txt", "0", nil, "pwned\n")
    .. member("leak", "1", "../../etc/hostname") .. member("in", "2", "lnk/keep.txt") .. ("\0"):rep(1024))
  run("mkdir /tmp/sn")
  local out, rc = run("tar xvf /tmp/sneaky.tar -C /tmp/sn")
  eq(rc, 2)
  eq(file("/tmp/out/keep.txt"), "keep\n", "nothing written through the link")
  has(out, "leak: links to ../../etc/hostname, outside the archive")
  ok(not file("/tmp/sn/leak"))
  -- the file went into a directory of that name; the link comes after and finds it there
  eq(file("/tmp/sn/lnk/keep.txt"), "pwned\n"); has(out, "lnk: file exists")
end)

test("tar: stricter modes come back for root, the perms file stays small", function()
  put("/tmp/m/secret", "s")
  run("chmod 600 /tmp/m/secret")
  run("tar cf /tmp/m.tar -C /tmp m")
  run("mkdir /home/root/r; tar xf /tmp/m.tar -C /home/root/r")
  eq(kernel.fs.stat("/home/root/r/m/secret").mode, tonumber("600", 8))
  local perms = file("/var/lib/perms") or ""
  has(perms, "/home/root/r/m/secret")
  -- the directory gets its group (root) back, but never the looser 777 /tmp had
  local dir = perms:match("([^\n]*) /home/root/r/m\n")
  ok(not dir or dir:match("^755 "), "the directory keeps its stricter mode: " .. tostring(dir))
  eq(kernel.fs.stat("/home/root/r/m").mode, tonumber("755", 8))
end)

test("tar: symbolic links", function()
  if not kernel.fs.link then return end
  run("mkdir /tmp/ln; echo t > /tmp/ln/target")
  ok(kernel.fs.link("target", "/tmp/ln/link"))
  has(run("tar cf /tmp/ln.tar -C /tmp ln; tar tvf /tmp/ln.tar"), "ln/link -> target")
  run("mkdir /tmp/ln2; tar xf /tmp/ln.tar -C /tmp/ln2")
  eq(kernel.fs.readlink("/tmp/ln2/ln/link"), "target")
end)

test("tar: archives open on a PC and the other way round", function()
  if not hostTar then return end
  local listed = io.popen("tar -tf " .. q(ROOT .. "/tmp/x.tar")):read("a")
  eq(listed, "src/\nsrc/a.txt\nsrc/sub/\nsrc/sub/b.txt\nsrc/sub/deep/\nsrc/sub/deep/c.txt\n")
  ok(sh("cd " .. q(ROOT .. "/tmp") .. " && tar --format=ustar -cf host.tar src"), "host tar packs")
  run("mkdir /tmp/fromhost; tar xf /tmp/host.tar -C /tmp/fromhost")
  eq(file("/tmp/fromhost/src/sub/b.txt"), string.rep("0123456789", 300))
  ok(sh("cd " .. q(ROOT .. "/tmp") .. " && tar --format=gnu -cf gnu.tar src"), "host tar packs (gnu)")
  has(run("tar tf /tmp/gnu.tar"), "src/sub/deep/c.txt")
end)


test("tar: only the named members", function()
  eq(run("tar -tf /tmp/x.tar src/sub/deep src/a.txt"), "src/a.txt\nsrc/sub/deep/\nsrc/sub/deep/c.txt\n")
  run("mkdir /tmp/pick")
  local _, rc = run("tar -xf /tmp/x.tar -C /tmp/pick src/a.txt")
  eq(rc, 0)
  eq(file("/tmp/pick/src/a.txt"), "hello\n")
  ok(not file("/tmp/pick/src/sub/b.txt"), "nothing else was unpacked")
  local out, bad = run("tar -xf /tmp/x.tar -C /tmp/pick src/nope")
  eq(bad, 2); has(out, "src/nope: not found in the archive")
end)


-- play (extra/play): songs on the speaker and on note blocks
test("play installs, plays notes on the speaker with the right pitch and length", function()
  lacks(run(P .. "-S play"), "error")
  local beeps = {}
  computer.beep = function(f, d) beeps[#beeps + 1] = { f, d } end
  local _, rc = run("play -t 6000 -n 'A4 C4 R A5*2 Bb4/2 C#5.'")
  eq(rc, 0)
  eq(#beeps, 5, "a rest makes no sound")
  local function near(a, b, what) ok(math.abs(a - b) < 0.01, what .. ": " .. a .. " vs " .. b) end
  near(beeps[1][1], 440, "A4"); near(beeps[2][1], 261.63, "C4"); near(beeps[3][1], 880, "A5")
  near(beeps[4][1], 466.16, "Bb4"); near(beeps[5][1], 554.37, "C#5")
  -- one beat at 6000 bpm is 10 ms, of which the speaker plays 90 %
  near(beeps[1][2] * 1000, 9, "one beat"); near(beeps[3][2] * 1000, 18, "*2")
  near(beeps[4][2] * 1000, 4.5, "/2"); near(beeps[5][2] * 1000, 13.5, "a dot adds half")
  has(run("play -n 'C9'"), "above 2000 Hz are skipped")
end)

test("play: the songs it brings, and mistakes with their line", function()
  local list = run("play -l")
  has(list, "ode-to-joy"); has(list, "Ode to Joy (Beethoven"); has(list, "korobeiniki"); has(list, "fur-elise")
  local beeps = {}
  computer.beep = function(f, d) beeps[#beeps + 1] = { f, d } end
  eq(select(2, run("play -t 6000 ode-to-joy")), 0)
  eq(#beeps, 62, "every note of the song")
  for _, song in ipairs({ "twinkle", "korobeiniki", "fur-elise" }) do
    eq(select(2, run("play -t 6000 " .. song)), 0, song .. " plays")
  end
  put("/tmp/bad.txt", "# broken\ntempo 100\nC4 D4 # a comment\nE4 X9\n")
  local out, rc = run("play /tmp/bad.txt")
  eq(rc, 1); has(out, "/tmp/bad.txt, line 4: not a note: X9")
  has(run("play -n 'C4/0'"), "not a length: C4/0")
  local _, missing = run("play nosuchsong")
  eq(missing, 1)
end)

test("play: note blocks take over from the speaker", function()
  local played, beeps = {}, 0
  computer.beep = function() beeps = beeps + 1 end
  plug("iron_noteblock", "nb000000-1", { playNote = function(_, n) played[#played + 1] = n end })
  run("play -t 6000 -n 'F#3 F#5 C4 C7 C2'")
  eq(table.concat(played, " "), "0 24 6 18 6", "two octaves from F#3, others moved into them")
  eq(beeps, 0)
  run("play -s -t 6000 -n 'C4'")
  eq(beeps, 1, "-s: the speaker anyway")
  undisk("nb000000-1")
end)

-- irc (extra/irc): a fake server behind a fake internet card
local function typed(text)
  local list = {}
  for _, cp in utf8.codes(text) do list[#list + 1] = { "key_down", "kbd", cp, 0 } end
  list[#list + 1] = { "key_down", "kbd", 13, 28 }
  return list
end

test("irc signs in, joins, chats, answers PING and quits", function()
  lacks(run(P .. "-S irc"), "error")
  local sent, asked, closedSock = {}, nil, false
  local incoming = {
    ":srv 433 * alice :Nickname is already in use",
    ":srv 001 alice_ :Welcome to the test network",
    ":srv 332 alice_ #byteos :All about ByteOS",
    ":bob!b@h PRIVMSG #byteos :hi there alice_",
    "PING :tick",
    ":carol!c@h PRIVMSG #byteos :\1ACTION waves\1",
    ":dave!d@h PRIVMSG alice_ :psst",
  }
  local sock = {
    finishConnect = function() return true end,
    read = function() local l = table.remove(incoming, 1); return l and (l .. "\r\n") or "" end,
    write = function(s)
      sent[#sent + 1] = s
      if s:match("^JOIN #byteos") then table.insert(incoming, 1, ":alice_!a@h JOIN #byteos") end
      return true
    end,
    close = function() closedSock = true end,
  }
  plug("internet", "inet-aaaa", { connect = function(host, port) asked = host .. ":" .. port; return sock end })
  local keys = {}
  for _, s in ipairs({ "hello world", "/me waves back", "/msg dave hi", "/nope" }) do
    for _, sig in ipairs(typed(s)) do keys[#keys + 1] = sig end
  end
  for _, sig in ipairs(typed("/quit bye")) do keys[#keys + 1] = sig end
  signals(keys)
  local out, rc = run("irc -n alice -p 6697 -j byteos irc.example.net")
  undisk("inet-aaaa") -- before anything can fail: a later irc would find it
  eq(rc, 0, out)
  eq(asked, "irc.example.net:6697")
  local all = table.concat(sent)
  eq(sent[1], "NICK alice\r\n"); eq(sent[2], "USER alice 0 * :ByteOS user\r\n")
  has(all, "NICK alice_\r\n", "a taken nick gets a _")
  has(all, "JOIN #byteos\r\n"); has(all, "PONG :tick\r\n")
  has(all, "PRIVMSG #byteos :hello world\r\n")
  has(all, "PRIVMSG #byteos :\1ACTION waves back\1\r\n")
  has(all, "PRIVMSG dave :hi\r\n"); has(all, "QUIT :bye\r\n")
  ok(closedSock, "the connection was closed")
  has(out, "irc.example.net  #byteos  alice_", "the status line")
  has(out, "topic of #byteos: All about ByteOS")
  has(out, "<bob> hi there alice_"); has(out, "* carol waves"); has(out, "*dave* psst")
  has(out, "<alice_> hello world"); has(out, "-> *dave* hi")
  has(out, "unknown command /nope")
  has(out, "[#byteos] ", "the input line names where text goes")
end)

test("irc without a usable internet card", function()
  has(run("irc"), "no internet card")
  plug("internet", "inet-aaab", { request = function() end })
  has(run("irc"), "cannot open TCP connections")
  undisk("inet-aaab")
  has(run("irc -n '1bad'"), "not a usable nick")
end)
