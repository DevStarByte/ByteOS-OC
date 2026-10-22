--[[
  tools/test/pkgrepo.lua - the package repositories for a test case

    local P = dofile(REPO .. "/tools/test/pkgrepo.lua")
    if not P then return end      -- no packages branch here: skipped
    run(P .. "-S mytool")

  Builds every package with tools/mkrepo.lua into /srv of the test system
  and points pacman at it. The sources come from $BYTEOS_PKGS (a packages
  checkout) or else the packages branch. Returns the pacman command to
  install without questions, or nil (after a skip notice) when there are
  no sources.
]]--
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
if not found then print("PASS packages branch not found, skipped"); return nil end
os.execute(("%s %s/tools/mkrepo.lua %s >/dev/null"):format(q(LUA), q(REPO), q(SRV)))
put("/etc/pacman.conf", "[options]\nHoldPkg = byteos\nSigLevel = Never\n\n[core]\nServer = /srv/core\n\n[extra]\nServer = /srv/extra\n")
return "pacman --noconfirm "
