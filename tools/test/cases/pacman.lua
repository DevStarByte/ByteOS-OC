-- pacman: repos built with tools/mkrepo.lua, signatures, dependencies,
-- conflicts, config files, hooks, makepkg -U and the queries.
users()
local LUA = arg[-1] or "lua"
local function q(p) return "'" .. p .. "'" end
local KEY = os.tmpname()
os.execute("openssl ecparam -name prime256v1 -genkey -noout -out " .. q(KEY))
os.execute("mkdir -p " .. q(ROOT .. "/etc/pacman.d"))
os.execute("openssl ec -in " .. q(KEY) .. " -pubout -outform DER 2>/dev/null | base64 > " .. q(ROOT .. "/etc/pacman.d/test.pub"))

local function pkg(name, pkgbuild, files, install)
  local dir = ROOT .. "/srv/pkgs/test/" .. name
  os.execute("rm -rf " .. q(dir))
  for path, data in pairs(files or { ["/usr/bin/" .. name .. ".lua"] = "return 0\n" }) do put("/srv/pkgs/test/" .. name .. "/files" .. path, data) end
  put("/srv/pkgs/test/" .. name .. "/PKGBUILD.lua", pkgbuild)
  if install then put("/srv/pkgs/test/" .. name .. "/" .. name .. ".install", install) end
end
local function build(sign)
  os.execute(("%s %s/tools/mkrepo.lua %s %s >/dev/null"):format(q(LUA), q(REPO), sign == false and "" or ("--key " .. q(KEY)), q(ROOT .. "/srv")))
end

pkg("libx", 'return { name = "libx", version = "2.0" }')
pkg("app", 'return { name = "app", version = "1.0", depends = { "libx>=2" } }')
pkg("old", 'return { name = "old", version = "1.0", depends = { "libx<2" } }')
pkg("newtool", 'return { name = "newtool", version = "1.0", conflicts = { "libx<2" } }')
pkg("evil", 'return { name = "evil", version = "1.0" }', { ["/bin/ls.lua"] = "return 0\n" })
pkg("conf", 'return { name = "conf", version = "1.0", backup = { "/etc/conf.conf" }, install = "conf.install" }',
  { ["/etc/conf.conf"] = "setting=1\n", ["/usr/bin/conf.lua"] = "return 0\n", ["/usr/bin/conf-old.lua"] = "return 0\n" },
  'function post_install(v) fs.writeAll("/tmp/hook.log", (fs.readAll("/tmp/hook.log") or "") .. "install " .. v .. "\\n") end\n' ..
  'function post_upgrade(n, o) fs.writeAll("/tmp/hook.log", fs.readAll("/tmp/hook.log") .. "upgrade " .. o .. " " .. n .. "\\n") end\n' ..
  'function pre_remove(v) fs.writeAll("/tmp/hook.log", fs.readAll("/tmp/hook.log") .. "remove " .. v .. "\\n") end\n')
build()
put("/etc/pacman.conf", "[options]\nHoldPkg = byteos\nSigLevel = Optional\nTrustedKey = /etc/pacman.d/test.pub\n\n[test]\nServer = /srv/test\n")
local P = "pacman --noconfirm "

test("Optional without a data card: one warning, sync works", function()
  local out = run(P .. "-Sy")
  has(out, "signatures are not checked")
  ok(file("/var/lib/pacman/sync/test.db"), "database synced")
end)

test("with a data card a tampered database is rejected, the old one kept", function()
  useDatacard(true)
  lacks(run(P .. "-Sy"), "error")
  put("/srv/test/test.db", file("/srv/test/test.db") .. "\nname = evil2\nversion = 1-1\n")
  local out = run(P .. "-Sy")
  has(out, "signature is invalid"); lacks(out, "check the Server lines")
  lacks(file("/var/lib/pacman/sync/test.db"), "evil2")
  build()
  useDatacard(false)
end)

test("Required: no data card or no signature, no packages", function()
  put("/etc/pacman.conf", file("/etc/pacman.conf"):gsub("SigLevel = Optional", "SigLevel = Required"))
  has(run(P .. "-Sy"), "need a tier 3 data card")
  useDatacard(true)
  build(false)
  os.remove(ROOT .. "/srv/test/test.db.sig")
  has(run(P .. "-Sy"), "not signed")
  build()
  lacks(run(P .. "-Sy"), "error")
  useDatacard(false)
  put("/etc/pacman.conf", file("/etc/pacman.conf"):gsub("SigLevel = Required", "SigLevel = Optional"))
end)

test("makepkg and -U; versioned dependencies and conflicts", function()
  put("/home/root/libx1/PKGBUILD.lua", 'return { name = "libx", version = "1.0" }')
  put("/home/root/libx1/files/usr/bin/libx.lua", "return 1\n")
  put("/home/root/legacy/PKGBUILD.lua", 'return { name = "legacy", version = "1.0", depends = { "libx<2" } }')
  put("/home/root/legacy/files/usr/bin/legacy.lua", "return 0\n")
  has(run("makepkg /home/root/libx1"), "Finished making: libx-1.0-1.bpk")
  run("makepkg /home/root/legacy")
  run(P .. "-U /home/root/libx1/libx-1.0-1.bpk /home/root/legacy/legacy-1.0-1.bpk")
  eq(run("pacman -Q"), "byteos " .. file("/var/lib/pacman/local/byteos/desc"):match("version=(%S+)") .. "\nlegacy 1.0-1\nlibx 1.0-1\n")
  has(run(P .. "-S app"), "breaks dependency 'libx<2' required by legacy")
  has(run(P .. "-S newtool"), "newtool and libx are in conflict")
  run(P .. "-S old")
  ok(file("/var/lib/pacman/local/old/desc"), "old installed: libx 1.0 satisfies libx<2")
  has(run(P .. "-R libx"), "breaks dependency")
  run(P .. "-R legacy old")
  run(P .. "-S app")
  has(run("pacman -Q"), "libx 2.0-1")
  lacks(run(P .. "-S newtool"), "are in conflict")
  has(run(P .. "-R libx"), "required by app")
end)

test("files owned by another package or byteos are refused", function()
  local out = run(P .. "-S evil")
  has(out, "/bin/ls.lua exists in both 'evil' and 'byteos'")
  eq(file("/bin/ls.lua"):find("return 0\n", 1, true) == 1 and #file("/bin/ls.lua") == 9, false, "ls untouched")
end)

test("config files: .pacnew on upgrade, .pacsave on removal; hooks", function()
  run(P .. "-S conf")
  eq(file("/tmp/hook.log"), "install 1.0-1\n")
  put("/etc/conf.conf", "setting=MINE\n")
  pkg("conf", 'return { name = "conf", version = "1.0", rel = 2, backup = { "/etc/conf.conf" }, install = "conf.install" }',
    { ["/etc/conf.conf"] = "setting=2\n", ["/usr/bin/conf.lua"] = "return 0\n" }, file("/srv/pkgs/test/conf/conf.install"))
  build()
  run(P .. "-Sy")
  has(run(P .. "-Su"), "installed as /etc/conf.conf.pacnew")
  eq(file("/etc/conf.conf"), "setting=MINE\n"); eq(file("/etc/conf.conf.pacnew"), "setting=2\n")
  eq(file("/usr/bin/conf-old.lua"), nil, "file dropped by the new version is removed")
  has(file("/tmp/hook.log"), "upgrade 1.0-1 1.0-2")
  has(run(P .. "-R conf"), "saved as /etc/conf.conf.pacsave")
  has(file("/tmp/hook.log"), "remove 1.0-2")
end)

test("-Ql, -Qo, -Sc", function()
  eq(run("pacman -Ql app"), "app /usr/bin/app.lua\n")
  has(run("pacman -Qo /usr/bin/app.lua"), "is owned by app 1.0-1")
  has(run("pacman -Qo /bin/ls.lua"), "is owned by byteos")
  has(run("pacman -Qo /etc/nope"), "No package owns /etc/nope")
  put("/var/cache/pacman/pkg/stale-1.0-1.bpk", "x")
  has(run(P .. "-Sc"), "removed")
  eq(file("/var/cache/pacman/pkg/stale-1.0-1.bpk"), nil)
  has(run(P .. "-Sc"), "already empty")
end)

test("a package whose SHA-256 does not match is not installed", function()
  pkg("plain", 'return { name = "plain", version = "1.0" }')
  build(false)
  os.remove(ROOT .. "/srv/test/test.db.sig")
  put("/srv/test/test.db", (file("/srv/test/test.db"):gsub("(name = plain.-sha256 = )%x", "%10")))
  run(P .. "-Sy")
  has(run(P .. "-S plain"), "is corrupted")
  eq(file("/var/lib/pacman/local/plain/desc"), nil)
end)

os.remove(KEY)
