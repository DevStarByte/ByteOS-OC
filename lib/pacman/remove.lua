--[[
  /lib/pacman/remove.lua - pacman: removing packages (-R, -Rs, -Rn)

  A part of /bin/pacman.lua, loaded into the same run when one of its
  functions is first needed (see PARTS there); P is shared by all parts.
]]--
local fs, bpk, T = k.fs, require("bpk"), term.theme
local CONF_PATH, LOCAL_DIR, SYNC_DIR, CACHE_DIR = P.CONF_PATH, P.LOCAL_DIR, P.SYNC_DIR, P.CACHE_DIR

-- Packages that -R refuses to remove (HoldPkg in pacman.conf).
local function held()
  local set = { byteos = true }
  for n in ((P.readRepos().options or {}).HoldPkg or ""):gmatch("%S+") do set[n] = true end
  return set
end

local function removePackage(name, idx, total, nosave)
  local label = ("(%d/%d) removing %s"):format(idx, total, name)
  P.progress(label, 0)
  local i = P.localInfo(name)
  local hooks = P.readIf(LOCAL_DIR .. "/" .. name .. "/install")
  P.runHook(hooks, "pre_remove", i.version)
  local crcs, notes = P.backupCrcs(i), {}
  for _, f in ipairs(P.localFiles(name)) do
    if fs.exists(f) and not fs.isDirectory(f) then
      if crcs[f] and not nosave and P.crcOf(P.readIf(f)) ~= crcs[f] then
        if fs.exists(f .. ".pacsave") then fs.remove(f .. ".pacsave") end
        fs.rename(f, f .. ".pacsave")
        notes[#notes + 1] = f .. " saved as " .. f .. ".pacsave"
      else
        fs.remove(f)
      end
    end
  end
  fs.remove(LOCAL_DIR .. "/" .. name)
  P.progress(label, 1); term.write("\n")
  k.log(("removed %s (%s)"):format(name, tostring(i.version)), "pacman")
  P.runHook(hooks, "post_remove", i.version)
  for _, note in ipairs(notes) do P.warn(note) end
end

-- Installed packages that need `name`, leaving out those in `except`.
local function requiredBy(name, except)
  local out = {}
  for _, n in ipairs(P.installedNames()) do
    if not (except and except[n]) then
      for _, d in ipairs(P.localInfo(n).depend) do
        if P.depName(d) == name then out[#out + 1] = n; break end
      end
    end
  end
  return out
end

-- -R [-s] [-n]: recursive also takes the dependencies of what goes that
-- were installed as dependencies and that nothing staying needs; nosave
-- deletes changed config files instead of keeping them as .pacsave.
local function remove(targets, opts)
  opts = opts or {}
  if #targets == 0 then P.err("no targets specified (use -h for help)"); return 1 end
  local hold, set, labels = held(), {}, {}
  for _, t in ipairs(targets) do set[t] = true end
  for _, pkg in ipairs(targets) do
    if pkg == "bytebios" then
      local st, i = P.biosStatus()
      if st ~= "current" and st ~= "outdated" then P.err("target not found: bytebios"); return 1 end
      if not P.bios().canRestore() then
        P.err("the BIOS from before ByteBIOS was not saved, so bytebios cannot be removed")
        return 1
      end
      labels[#labels + 1] = "bytebios-" .. i.installed
    elseif not P.isInstalled(pkg) then
      P.err("target not found: " .. pkg); return 1
    elseif hold[pkg] then
      P.err(pkg .. " is part of the base system and cannot be removed (HoldPkg)")
      return 1
    else
      labels[#labels + 1] = pkg .. "-" .. (P.localInfo(pkg).version or "?")
    end
  end
  P.info("checking dependencies...")
  if opts.recursive then
    targets = { table.unpack(targets) }
    local i = 1
    while i <= #targets do -- targets grows while it is walked: deps of deps
      local pi = targets[i] ~= "bytebios" and P.localInfo(targets[i])
      for _, d in ipairs(pi and pi.depend or {}) do
        local dn = P.depName(d)
        local di = not set[dn] and not hold[dn] and P.localInfo(dn)
        if di and di.reason == "dependency" and #requiredBy(dn, set) == 0 then
          set[dn] = true
          targets[#targets + 1] = dn
          labels[#labels + 1] = dn .. "-" .. (di.version or "?")
        end
      end
      i = i + 1
    end
  end
  local broken = false
  for _, n in ipairs(P.installedNames()) do
    if not set[n] then
      for _, d in ipairs(P.localInfo(n).depend) do
        if set[P.depName(d)] then
          P.err(("removing %s breaks dependency '%s' required by %s"):format(P.depName(d), d, n))
          broken = true
        end
      end
    end
  end
  if broken then return 1 end
  if not P.confirmPackages(labels, "Do you want to remove these packages?") then return 1 end
  P.header("Processing package changes...")
  local ok = true
  for i, pkg in ipairs(targets) do
    if pkg == "bytebios" then
      local label = ("(%d/%d) restoring the previous BIOS"):format(i, #targets)
      P.progress(label, 0)
      local done, e = P.bios().restore()
      if done then P.progress(label, 1); term.write("\n")
      else term.write("\n"); P.err("bytebios: " .. e); ok = false end
    else
      removePackage(pkg, i, #targets, opts.nosave)
    end
  end
  return ok and 0 or 1
end

P.held = held
P.removePackage = removePackage
P.requiredBy = requiredBy
P.remove = remove
