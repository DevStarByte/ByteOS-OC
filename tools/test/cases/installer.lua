-- install.lua under (a stand-in for) OpenOS, installing from a disk:
-- only the system goes on the target, it erases what was there, it leaves
-- what pacman needs, and the result boots.
local LUA = arg[-1] or "lua"
local function q(p) return "'" .. p .. "'" end
local base = os.tmpname()
os.remove(base)
local src, target = base .. "-src", base .. "-target"
os.execute(("mkdir -p %s %s && cd %s && cp -r init.lua install.lua boot sbin lib bin etc home var usr README.md tools %s/"):format(q(src), q(target), q(REPO), q(src)))
local old = io.open(target .. "/old.txt", "w"); old:write("old\n"); old:close()

-- source 2 (disk); the only disk with ByteOS is offered as number 1;
-- target 1; erase: yes; flash ByteBIOS: yes; reboot: no
local h = io.popen(("ANSWERS='2|1|1|yes|yes|no' NO_INTERNET=1 %s %s/tools/test/openos.lua %s/install.lua %s %s 2>&1")
  :format(q(LUA), q(REPO), q(REPO), q(target), q(src)))
local out = h:read("a")
h:close()
local function on(path) local f = io.open(target .. path, "rb"); if not f then return nil end local d = f:read("a"); f:close(); return d end

test("the installer finishes and flashes ByteBIOS", function()
  has(out, "ByteOS "); has(out, "is on hdd00001")
  has(out, "[eeprom: label=ByteBIOS, ByteBIOS=true]")
  has(out, "[boot address = hdd00001-aaaa]")
  lacks(out, "CRASH"); lacks(out, "Error")
end)

test("only the system is installed and the old content is gone", function()
  eq(on("/old.txt"), nil, "erased")
  ok(on("/init.lua") and on("/boot/kernel.lua") and on("/bin/pacman.lua") and on("/usr/share/man/byteshell.txt"), "system files")
  eq(on("/README.md"), nil, "no README")
  eq(on("/install.lua"), nil, "no installer")
  eq(on("/tools/test/run.lua"), nil, "no tools")
end)

test("what pacman needs: the old BIOS, pristine /etc, the version", function()
  eq(on("/var/lib/pacman/byteos/eeprom.orig"), "-- Lua BIOS\nlocal init")
  eq(on("/var/lib/pacman/byteos/pristine/etc/pacman.conf"), on("/etc/pacman.conf"))
  local release = on("/etc/os-release"):match("VERSION_ID=([%d%.]+)")
  has(on("/var/lib/pacman/local/byteos/desc"), "version=" .. release)
end)

test("the installed system boots", function()
  local case = base .. "-case.lua"
  local f = io.open(case, "w")
  f:write('test("boot", function() eq(run("whoami"), "root\\n"); has(run("pacman -Q"), "byteos") end)\n')
  f:close()
  local b = io.popen(("%s %s/tools/test/boot.lua %s %s 2>&1"):format(q(LUA), q(REPO), q(target), q(case)))
  local result = b:read("a")
  b:close()
  os.remove(case)
  has(result, "PASS boot")
end)

os.execute("rm -rf " .. q(src) .. " " .. q(target))
