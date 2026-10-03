-- The packages on the packages branch: built with tools/mkrepo.lua,
-- installed with pacman and tried out on fake hardware. The sources come
-- from $BYTEOS_PKGS (a packages checkout) or else the packages branch.
users()
local LUA = arg[-1] or "lua"
local function q(p) return "'" .. p:gsub("'", "'\\''") .. "'" end
local SRV = ROOT .. "/srv"
os.execute("mkdir -p " .. q(SRV))
local src = os.getenv("BYTEOS_PKGS")
local found
if src then
  found = os.execute("cp -r " .. q(src .. "/pkgs") .. " " .. q(SRV)) == true
else
  for _, ref in ipairs({ "packages", "origin/packages" }) do
    if os.execute(("git -C %s archive %s pkgs 2>/dev/null | tar -x -C %s 2>/dev/null"):format(q(REPO), ref, q(SRV))) == true then
      found = true; break
    end
  end
end
if not found then print("PASS packages branch not found, skipped"); return end
os.execute(("%s %s/tools/mkrepo.lua %s >/dev/null"):format(q(LUA), q(REPO), q(SRV)))
put("/etc/pacman.conf", "[options]\nHoldPkg = byteos\nSigLevel = Never\n\n[core]\nServer = /srv/core\n\n[extra]\nServer = /srv/extra\n")
local P = "pacman --noconfirm "
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

test("rsh runs commands as the user, over the network", function()
  run("systemctl start rshd")
  for _ = 1, 5 do kernel.event.pull(0.01) end
  answers({ "alicepw" })
  local out, rc = run("rsh alice@" .. ME .. " whoami")
  has(out, "alice"); eq(rc, 0)
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
