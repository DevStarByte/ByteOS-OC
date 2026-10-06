-- Memory at the login prompt: which libraries stay loaded and how much
-- their code takes. OpenComputers computers have little memory (a Tier 1.5
-- stick is about 460 KiB on a 64-bit server), so this guards against a
-- library that should come and go staying loaded, or the resident code
-- quietly growing. Numbers are measured with the PC's Lua: OpenComputers'
-- own counting differs, the trend is what matters.
_G.kstatus = function() end
put("/etc/.installed", "HOST=byteos")
users()
local screenDev = term.console
local readAnswer = screenDev.read
screenDev.read = function(...)
  local a = readAnswer(...)
  if a == nil then error("__end_of_test__", 0) end
  return a
end
-- a command typed at the prompt notes what is loaded right then
put("/bin/memsnap.lua", [[
local names = {}
for n in pairs(package.loaded) do names[#names + 1] = n end
_G.RESIDENT = names
]])

-- what a library's code takes, loaded on its own
local function codeKiB(name)
  local f = io.open(ROOT .. "/lib/" .. name .. ".lua")
  if not f then return 0 end
  local src = f:read("a"); f:close()
  collectgarbage(); collectgarbage()
  local before = collectgarbage("count")
  local chunk = load(src, "=" .. name, "t", {})
  collectgarbage(); collectgarbage()
  local kib = collectgarbage("count") - before
  chunk = nil
  return kib
end

local EXPECTED = { clock = true, lineedit = true, net = true, shell = true, systemd = true,
                   term = true, theme = true, tty = true }
local BUDGET = 145 -- KiB of library code at the prompt (134 when this was written)

test("at the prompt only the libraries in use stay loaded, within budget", function()
  keys({ "memsnap", "<enter>", "<ctrl+d>" }); answers({ "root", "rootpw" })
  pcall(assert(loadfile(ROOT .. "/sbin/init.lua", "t", _G)))
  ok(_G.RESIDENT, "the shell ran memsnap")
  table.sort(_G.RESIDENT)
  local total, list = 0, {}
  for _, name in ipairs(_G.RESIDENT) do
    ok(EXPECTED[name], "'" .. name .. "' stays loaded at the prompt (all: " .. table.concat(_G.RESIDENT, " ") .. ")")
    local kib = codeKiB(name)
    total = total + kib
    list[#list + 1] = ("%s %.1f"):format(name, kib)
  end
  ok(total <= BUDGET, ("library code at the prompt: %.1f KiB, budget %d KiB (%s)"):format(total, BUDGET, table.concat(list, ", ")))
end)

test("pacman lets go of its libraries and compiles only the parts it needs", function()
  local before = {}
  for n in pairs(package.loaded) do before[n] = true end
  local reads = {}
  local readAll = kernel.fs.readAll
  kernel.fs.readAll = function(p) reads[#reads + 1] = p; return readAll(p) end
  run("pacman -Q; pacman -Qi byteos; pacman -Ql byteos > /tmp/ql")
  kernel.fs.readAll = readAll
  for n in pairs(package.loaded) do ok(before[n], "pacman left '" .. n .. "' loaded") end
  local parts = table.concat(reads, " ")
  has(parts, "/lib/pacman/query.lua")
  lacks(parts, "/lib/pacman/install.lua", "a query does not load the installer")
  lacks(parts, "/lib/pacman/sync.lua", "nor the downloader")
end)

test("a pipe holds its data about once, not once per stage", function()
  local data = string.rep("hello world, a line of text\n", 6000) -- 164 KiB
  put("/tmp/big.txt", data)
  local size = #data / 1024
  data = nil
  local function livePeak(cmd)
    run(cmd) -- warm up
    collectgarbage(); collectgarbage()
    local low = collectgarbage("count"); local peak = low
    debug.sethook(function()
      collectgarbage()
      local c = collectgarbage("count")
      if c > peak then peak = c end
      if c < low then low = c end
    end, "", 300)
    local out = run(cmd)
    debug.sethook()
    return peak - low, out
  end
  for _, cmd in ipairs({ "cat /tmp/big.txt | grep zzz | wc -l", "grep -c hello /tmp/big.txt" }) do
    local kib, out = livePeak(cmd)
    ok(out:match("%d"), cmd .. " ran")
    ok(kib < size * 1.3, ("%s: %.0f KiB for a %.0f KiB file"):format(cmd, kib, size))
  end
end)
