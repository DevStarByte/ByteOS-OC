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

test("install reasons; -Rs takes unneeded dependencies along, -Rn the config files", function()
  pkg("app2", 'return { name = "app2", version = "1.0", depends = { "libx" } }')
  pkg("tool", 'return { name = "tool", version = "1.0", depends = { "toollib" } }')
  pkg("toollib", 'return { name = "toollib", version = "1.0", depends = { "toolbase" } }')
  pkg("toolbase", 'return { name = "toolbase", version = "1.0" }')
  build()
  run(P .. "-Sy")
  run(P .. "-R app libx")
  local L = "/var/lib/pacman/local/"

  run(P .. "-S tool")
  has(run("pacman -Qi tool"), "Explicitly installed")
  has(run("pacman -Qi toollib"), "Installed as a dependency")
  eq(run("pacman -Qdtq"), "", "no orphans while tool needs them")
  run(P .. "-R tool")
  eq(run("pacman -Qdtq"), "toollib\n", "toolbase is still needed by toollib")
  has(run("pacman -Qd"), "toolbase 1.0-1")
  run(P .. "-S tool")
  has(run("pacman -Qi toollib"), "Installed as a dependency", "a reinstall keeps the reason")

  local out = run(P .. "-Rs tool")
  has(out, "tool-1.0-1"); has(out, "toollib-1.0-1"); has(out, "toolbase-1.0-1")
  ok(not file(L .. "toollib/desc") and not file(L .. "toolbase/desc"), "dependencies of dependencies went too")

  -- a dependency another package still needs stays
  run(P .. "-S app app2")
  has(run("pacman -Qi libx"), "Installed as a dependency")
  run(P .. "-Rs app")
  ok(file(L .. "libx/desc"), "libx stays: app2 needs it")
  run(P .. "-Rs app2")
  ok(not file(L .. "libx/desc"), "and goes with the last one needing it")

  -- what was installed on purpose stays
  run(P .. "-S toolbase")
  run(P .. "-S tool")
  run(P .. "-Rs tool")
  ok(file(L .. "toolbase/desc"), "toolbase was installed explicitly")
  ok(not file(L .. "toollib/desc"))
  has(run(P .. "-D --asdeps toolbase"), "installed as dependency")
  eq(run("pacman -Qdtq"), "toolbase\n")
  has(run("pacman -Qe"), "byteos")
  lacks(run("pacman -Qe"), "toolbase")
  -- orphans away, as on Arch: the targets come through the pipe
  out = run("pacman -Qdtq | " .. P .. "-Rns -")
  has(out, "toolbase-1.0-1")
  ok(not file(L .. "toolbase/desc"), "the orphan is gone")
  has(run("pacman -Qdtq | " .. P .. "-Rns -"), "no targets specified")

  -- -n: a changed config file is deleted, not kept as .pacsave
  run(P .. "-S conf")
  put("/etc/conf.conf", "setting=MINE\n")
  os.remove(ROOT .. "/etc/conf.conf.pacsave")
  out = run(P .. "-Rns conf")
  lacks(out, "pacsave")
  eq(file("/etc/conf.conf"), nil); eq(file("/etc/conf.conf.pacsave"), nil)

  as("bob", function()
    eq(select(2, run("pacman -Qdt")), 0, "anyone may look")
    has(run("pacman -Rs conf"), "unless you are root")
  end)
end)

test("GitHub servers: the database and its packages come from one commit", function()
  build()
  local SHA = string.rep("ab", 20)
  local RAW = "https://raw.githubusercontent.com/owner/repo/"
  local routes = {
    ["https://api.github.com/repos/owner/repo/commits/packages"] = function(h)
      return h.Accept == "application/vnd.github.sha" and (SHA .. "\n") or nil
    end,
    -- what a cache may still hand out for the branch: a database from before
    [RAW .. "packages/test/test.db"] = "name = ghost\nversion = 9-1\n",
    [RAW .. SHA .. "/test/test.db"] = file("/srv/test/test.db"),
    [RAW .. SHA .. "/test/test.db.sig"] = file("/srv/test/test.db.sig"),
    [RAW .. SHA .. "/test/toolbase-1.0-1.bpk"] = file("/srv/test/toolbase-1.0-1.bpk"),
  }
  local asked = internetCard(routes)
  local conf = file("/etc/pacman.conf")
  put("/etc/pacman.conf", (conf:gsub("Server = /srv/test", "Server = " .. RAW .. "packages/test")))
  lacks(run(P .. "-Syy"), "error")
  lacks(file("/var/lib/pacman/sync/test.db"), "ghost", "not the cached branch copy")
  lacks(run(P .. "-S toolbase"), "error")
  ok(file("/var/lib/pacman/local/toolbase/desc"), "installed from the pinned commit")
  has(table.concat(asked, "\n"), RAW .. SHA .. "/test/toolbase-1.0-1.bpk")
  lacks(table.concat(asked, "\n"), RAW .. "packages/test/test.db", "the branch URL was not used")
  run(P .. "-R toolbase")
  put("/etc/pacman.conf", conf)
  undisk("inet0000-test")
end)

test("mkrepo keeps the previous version of a package for one more build", function()
  pkg("toolbase", 'return { name = "toolbase", version = "1.1" }')
  build()
  ok(file("/srv/test/toolbase-1.1-1.bpk"), "the new one")
  ok(file("/srv/test/toolbase-1.0-1.bpk"), "the old one is kept for a stale database")
  pkg("toolbase", 'return { name = "toolbase", version = "1.2" }')
  build()
  ok(file("/srv/test/toolbase-1.1-1.bpk"), "the previous one stays")
  eq(file("/srv/test/toolbase-1.0-1.bpk"), nil, "the one before goes")
end)

test("groups, optional dependencies and meta packages", function()
  pkg("kitone", 'return { name = "kitone", version = "1.0", groups = { "kit" }, optdepends = { "libx: faster", "kittwo" } }')
  pkg("kittwo", 'return { name = "kittwo", version = "1.0", groups = { "kit", "extras" } }')
  put("/srv/pkgs/test/bundle/PKGBUILD.lua", 'return { name = "bundle", version = "1.0", depends = { "kitone" } }')
  put("/srv/pkgs/test/badgroup/PKGBUILD.lua", 'return { name = "badgroup", version = "1.0", groups = { "no spaces" } }')
  build()
  eq(file("/srv/test/badgroup-1.0-1.bpk"), nil, "a bad group name stops the build")
  os.execute("rm -rf " .. q(ROOT .. "/srv/pkgs/test/badgroup"))
  build()
  ok(file("/srv/test/bundle-1.0-1.bpk"), "a meta package needs no files/")
  run(P .. "-Sy")
  eq(run("pacman -Sg kit"), "kit kitone\nkit kittwo\n")
  has(run("pacman -Sg"), "extras kittwo\n")
  local si = run("pacman -Si kitone")
  has(si, "Groups          : kit"); has(si, "Optional Deps   : libx: faster")
  has(run("pacman -Sg nokit"), "group 'nokit' was not found")

  local out = run(P .. "-S kit")
  has(out, "There are 2 members in group kit:")
  has(out, "Optional dependencies for kitone")
  has(out, "    kittwo [installed]", "kittwo came in with the group")
  eq(run("pacman -Qg kit"), "kit kitone\nkit kittwo\n")
  has(run("pacman -Qi kitone"), "Groups          : kit")
  has(run("pacman -Qi kitone"), "                  kittwo [installed]")
  run(P .. "-R kitone kittwo")

  lacks(run(P .. "-S bundle"), "error")
  ok(file("/var/lib/pacman/local/bundle/desc"), "the meta package is installed")
  has(file("/var/lib/pacman/local/kitone/desc"), "reason = dependency")
  run(P .. "-Rs bundle")
  eq(file("/var/lib/pacman/local/kitone/desc"), nil, "its dependency went with it")
end)

os.remove(KEY)
