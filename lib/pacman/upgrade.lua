--[[
  /lib/pacman/upgrade.lua - pacman: pacman -Syu: packages and the byteos base system, and --rollback

  A part of /bin/pacman.lua, loaded into the same run when one of its
  functions is first needed (see PARTS there); P is shared by all parts.
]]--
local bpk, T = require("bpk"), term.theme

-- ---- Base system -----------------------------------------------------------
-- The OS itself is the "byteos" package. It is in no repo database: pacman
-- upgrades it file by file from the git repository named in pacman.conf.
local function baseRepo()
  local o = P.readRepos().options or {}
  return o.BaseRepo or "DevStarByte/ByteOS-OC", o.BaseBranch or "master"
end

-- Returns the pending base upgrade, or nil if there is none / it cannot
-- be checked right now (the reason is printed).
local function checkBase()
  if not require("internet").available() then
    P.info(" no internet card: skipping the byteos base system")
    return nil
  end
  local repo, branch = baseRepo()
  local up, e = require("sysupgrade").check(repo, branch)
  if not up then P.warn("cannot check byteos for updates: " .. e); return nil end
  if up.uptodate then return nil end
  return up
end

local function upgradeBase(up)
  local sysupgrade = require("sysupgrade")
  P.header("Retrieving byteos " .. up.version .. " from " .. up.repo .. "...")
  local ok, e = sysupgrade.download(up, P.progress)
  if not ok then
    term.write("\n")
    P.err("failed to retrieve byteos: " .. e)
    P.info("the base system was not changed")
    return false
  end
  P.progress(("downloaded %d file%s"):format(up.downloaded, up.downloaded == 1 and "" or "s"), 1)
  term.write("\n")
  P.header("Upgrading byteos...")
  ok, e = sysupgrade.apply(up, function(label, frac) P.progress("upgrading " .. label, frac) end)
  if not ok then term.write("\n"); P.err(e); return false end
  P.progress(("upgraded byteos to %s"):format(up.version), 1)
  term.write("\n")
  k.log(("upgraded byteos (%s -> %s)"):format(tostring(up.oldVersion), up.version), "pacman")
  for _, path in ipairs(up.pacnew) do
    P.warn(path .. " installed as " .. path .. ".new")
  end
  return true
end

local function upgrade()
  P.sync()
  P.header("Starting full system upgrade...")
  local base = checkBase()
  local db, outdated = P.syncdb(), {}
  for _, n in ipairs(P.installedNames()) do
    local i, p = P.localInfo(n), db[n]
    if p and i and bpk.vercmp(p.version, i.version or "0") > 0 then outdated[#outdated + 1] = n end
  end
  local list = {}
  if #outdated > 0 then
    list = P.resolve(outdated)
    if not list or not P.noConflicts(list) then return 1 end
  end
  -- ByteBIOS is only reflashed if it is already on the EEPROM; another
  -- BIOS is never replaced without an explicit `pacman -S bytebios`.
  local biosState, biosInfo = P.biosStatus()
  local biosNow = not base and biosState == "outdated"
  if not base and #list == 0 and not biosNow then
    P.info(" there is nothing to do")
    if biosState == "foreign" then P.biosHint() end
    return 0
  end

  local labels = {}
  if base then labels[1] = "byteos-" .. base.version end
  if biosNow then labels[#labels + 1] = "bytebios-" .. (biosInfo.available or "?") end
  for _, n in ipairs(P.names(list)) do labels[#labels + 1] = n end
  local dl = P.sizes(list)
  if not P.confirmPackages(labels, "Proceed with installation?", dl) then return 1 end

  local ok = true
  if base then
    ok = upgradeBase(base)
    -- the upgrade may have brought a new /boot/eeprom.lua
    if ok and biosState ~= "foreign" and P.biosStatus() == "outdated" then biosNow = true end
  end
  if ok and biosNow then
    P.header("Updating ByteBIOS on the EEPROM...")
    ok = P.flashBios()
  end
  if ok and #list > 0 then
    local items = {}
    for _, p in ipairs(list) do items[#items + 1] = { db = p } end
    ok = P.commit(items)
  end
  if base and ok then
    term.cwrite(T.accent, ":: ")
    term.cwrite(T.bright, "byteos was upgraded; reboot to start the new version\n")
  end
  if ok and biosState == "foreign" then P.biosHint() end
  return ok and 0 or 1
end

local function rollback()
  local sysupgrade = require("sysupgrade")
  if not sysupgrade.canRollback() then P.err("there is no byteos upgrade to roll back"); return 1 end
  if not P.confirm("Restore byteos from before the last upgrade?") then return 1 end
  sysupgrade.rollback()
  P.info("previous byteos restored; reboot to use it")
  return 0
end

P.baseRepo = baseRepo
P.checkBase = checkBase
P.upgradeBase = upgradeBase
P.upgrade = upgrade
P.rollback = rollback
