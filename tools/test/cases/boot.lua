-- The whole of /sbin/init: boot lines, the first-boot wizard (driven by
-- key presses), logging in, a command, logging out, back at the login.
_G.kstatus = function(parts)
  local t = {}
  for _, p in ipairs(parts) do t[#t + 1] = p[1] end
  term.write(table.concat(t) .. "\n")
end
-- the login prompt never ends by itself: stop once the queued input is used up
local screen = term.console -- the fake screen behind the term module
local readAnswer = screen.read
screen.read = function(...)
  local a = readAnswer(...)
  if a == nil then error("__end_of_test__", 0) end
  return a
end
-- everything written, also what a later clear() wipes off the screen
local transcript = {}
local write = screen.write
screen.write = function(s) transcript[#transcript + 1] = tostring(s); return write(s) end
local function said() return table.concat(transcript) end

local function boot()
  local fn = assert(loadfile(ROOT .. "/sbin/init.lua", "t", _G))
  local done, err = pcall(fn)
  return done or err == "__end_of_test__", err
end

test("first boot: the wizard sets up the system", function()
  os.remove(ROOT .. "/etc/.installed")
  keys({
    "<enter>",                                   -- welcome
    "1", "<backspace>", "<backspace>", "<backspace>", "<backspace>", "<backspace>", "<backspace>",
    "box1", "<enter>",                           -- hostname: erase "ByteOS", type box1
    "2", "<end>", "<up>", "<enter>",             -- time zone: one up from the last one
    "3", "rootpw", "<enter>", "rootpw", "<enter>", -- root password, twice
    "6", "<enter>",                              -- install, confirm
    "<enter>",                                   -- "installation complete"
    -- the shell after logging in:
    "whoami", "<enter>", "<ctrl+d>",
  })
  answers({ "root", "rootpw" })
  local done, err = boot()
  ok(done, "init ran: " .. tostring(err))
  eq(file("/etc/hostname"), "box1\n")
  ok(file("/etc/timezone") and #file("/etc/timezone") > 2, "a time zone was written")
  ok(file("/etc/shadow"):match("^root:%$sha256%$"), "root password hashed")
  ok(file("/etc/.installed"), "marker written")
  eq(package.loaded.setup, nil, "the wizard is let go of after the first boot")
  local s = said()
  has(s, "box1 login:"); has(s, "root@box1 ~# "); has(s, "root\n")
end)

test("a later boot goes straight to the login; wrong passwords are refused", function()
  term.clear()
  transcript = {}
  keys({ "<ctrl+d>" })
  answers({ "root", "wrong", "root", "rootpw" })
  local done, err = boot()
  ok(done, "init ran: " .. tostring(err))
  local s = said()
  has(s, "Started ByteShell.")
  has(s, "Login incorrect")
  eq(package.loaded.setup, nil, "no wizard on a later boot")
  has(file("/var/log/messages"), "FAILED LOGIN for 'root'")
  has(file("/var/log/messages"), "session opened for user root")
end)
