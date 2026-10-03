-- Rolling back a byteos upgrade (pacman --rollback, and init.lua after a
-- failed boot) from the journal sysupgrade writes before it changes files.
local LIB = "/var/lib/pacman/byteos"
local function prepare()
  -- what apply() leaves behind: new files in place, old ones in the backup
  put("/bin/ls.lua", "-- new ls\n")
  put(LIB .. "/backup/bin/ls.lua", "-- old ls\n")
  put("/bin/added.lua", "-- added by the upgrade\n")
  put(LIB .. "/backup.list", "restore bin/ls.lua\nremove bin/added.lua\n")
  put(LIB .. "/pending", "abc\n")
end

test("pacman --rollback restores the files from before the upgrade", function()
  prepare()
  has(run("pacman --noconfirm --rollback"), "previous byteos restored")
  eq(file("/bin/ls.lua"), "-- old ls\n")
  eq(file("/bin/added.lua"), nil)
  eq(file(LIB .. "/backup.list"), nil)
  has(run("pacman --noconfirm --rollback"), "no byteos upgrade to roll back")
end)

test("init.lua rolls back by itself when the new version fails to boot", function()
  prepare()
  local src = file("/init.lua"):gsub("\r", "")
  local fnText = src:match("(local function rollbackUpdate%(%).-\nend)\n")
  ok(fnText, "rollbackUpdate found in init.lua")
  local boot = {
    exists = function(p) return file(p) ~= nil or os.execute("test -d '" .. ROOT .. p .. "'") == true end,
    remove = function(p) return os.execute("rm -rf '" .. ROOT .. p .. "'") == true end,
    makeDirectory = function(p) return os.execute("mkdir -p '" .. ROOT .. p .. "'") == true end,
    rename = function(a, b) return os.rename(ROOT .. a, ROOT .. b) ~= nil end,
  }
  local rollback = assert(load(fnText .. "\nreturn rollbackUpdate", "=init", "t",
    setmetatable({ boot = boot, readFile = file }, { __index = _G })))()
  eq(rollback(), true)
  eq(file("/bin/ls.lua"), "-- old ls\n")
  eq(file("/bin/added.lua"), nil)
  eq(rollback(), false, "nothing pending any more")
end)
