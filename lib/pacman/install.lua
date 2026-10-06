--[[
  /lib/pacman/install.lua - pacman: resolving dependencies, conflicts and installing (-S, -U)

  A part of /bin/pacman.lua, loaded into the same run when one of its
  functions is first needed (see PARTS there); P is shared by all parts.
]]--
local fs, bpk, T = k.fs, require("bpk"), term.theme
local sha256 = require("sha256")
local CONF_PATH, LOCAL_DIR, SYNC_DIR, CACHE_DIR = P.CONF_PATH, P.LOCAL_DIR, P.SYNC_DIR, P.CACHE_DIR

-- Repo packages for `targets` plus every dependency that is not installed
-- yet, dependencies first. `provided` names count as installed. Returns
-- the list, or nil after printing why.
local function resolve(targets, provided)
  if not P.synced() then P.sync() end
  local db = P.syncdb()
  local order, seen = {}, {}
  local function visit(name, by, op, want)
    local p = db[name]
    if not p then P.notFound(name, by); return false end
    if not P.satisfies(p.version, op, want) then
      P.err(("unresolvable dependency '%s%s%s'%s: the repositories have %s-%s"):format(
        name, op, want, by and (" (required by " .. by .. ")") or "", name, p.version))
      return false
    end
    if seen[name] then return true end
    seen[name] = true
    for _, d in ipairs(p.depend) do
      local dn, dop, dwant = P.parseDep(d)
      local have = provided and provided[dn]
      if not have then
        local i = P.localInfo(dn)
        have = i and i.version
      end
      if not P.satisfies(have, dop, dwant) then
        if not visit(dn, name, dop, dwant) then return false end
      end
    end
    order[#order + 1] = p
    return true
  end
  for _, t in ipairs(targets) do
    local name, op, want = P.parseDep(t)
    if not visit(name, nil, op, want) then return nil end
  end
  return order
end

-- Would installing these versions break what installed packages need
-- (bar: depend = foo<2 while foo-2.0 comes in)? Prints each case.
local function noBreaks(infos)
  local incoming = {}
  for _, p in ipairs(infos) do incoming[p.name] = p.version end
  local ok = true
  for _, n in ipairs(P.installedNames()) do
    if not incoming[n] then
      for _, d in ipairs((P.localInfo(n) or {}).depend or {}) do
        local dn, op, want = P.parseDep(d)
        if incoming[dn] and not P.satisfies(incoming[dn], op, want) then
          P.err(("installing %s (%s) breaks dependency '%s' required by %s"):format(dn, incoming[dn], d, n))
          ok = false
        end
      end
    end
  end
  return ok
end

-- "Packages (2) foo-1.0  bar-2.0", sizes, then the confirmation prompt.
local function confirmPackages(names, question, dlSize, inSize)
  term.write("\n")
  term.cwrite(T.bright, ("Packages (%d) "):format(#names))
  term.cwrite(T.fg, table.concat(names, "  ") .. "\n\n")
  if dlSize and dlSize > 0 then
    term.cwrite(T.bright, "Total Download Size:   ")
    term.cwrite(T.fg, P.kib(dlSize) .. "\n")
  end
  if inSize then
    term.cwrite(T.bright, "Total Installed Size:  ")
    term.cwrite(T.fg, P.kib(inSize) .. "\n")
  end
  if dlSize or inSize then term.write("\n") end
  return P.confirm(question)
end

-- ---- Transactions ----------------------------------------------------------
-- Conflicts between the packages `infos` (about to be installed) and the
-- installed packages or each other. The repo database has everything this
-- needs, so it runs before the confirmation prompt.
local function pkgConflicts(infos)
  local problems, names = {}, {}
  for _, p in ipairs(infos) do names[p.name] = p.version end
  for _, p in ipairs(infos) do
    for _, c in ipairs(p.conflict or {}) do
      local cn, op, want = P.parseDep(c)
      local other = names[cn] or (P.localInfo(cn) or {}).version
      if cn ~= p.name and other and P.satisfies(other, op, want) then
        problems[#problems + 1] = ("%s and %s are in conflict"):format(p.name, cn)
      end
    end
    for _, n in ipairs(P.installedNames()) do
      if n ~= p.name and not names[n] then
        for _, c in ipairs((P.localInfo(n) or {}).conflict or {}) do
          local cn, op, want = P.parseDep(c)
          if cn == p.name and P.satisfies(p.version, op, want) then
            problems[#problems + 1] = ("%s and %s are in conflict"):format(p.name, n)
          end
        end
      end
    end
  end
  return problems
end

-- Prints the conflicts among `infos`; true if there are none.
local function noConflicts(infos)
  local problems = pkgConflicts(infos)
  for _, p in ipairs(problems) do P.err(p) end
  if #problems > 0 then P.err("unresolvable package conflicts detected") end
  return #problems == 0 and noBreaks(infos)
end

-- Every problem that stops the transaction, checked before anything is
-- written: package conflicts and files another package (or the base
-- system) owns or that already exist on disk.
local function findConflicts(items)
  local infos = {}
  for _, it in ipairs(items) do infos[#infos + 1] = it.pkg.info end
  local problems = pkgConflicts(infos)
  local owner = {}
  for _, n in ipairs(P.installedNames()) do
    for _, f in ipairs(P.localFiles(n)) do owner[f] = n end
  end
  local incoming = {}
  for _, it in ipairs(items) do
    local name = it.pkg.info.name
    for _, p in ipairs(it.pkg.order) do
      local o = owner[p]
      if incoming[p] and incoming[p] ~= name then
        problems[#problems + 1] = ("%s exists in both '%s' and '%s'"):format(p, name, incoming[p])
      elseif o and o ~= name then
        problems[#problems + 1] = ("%s exists in both '%s' and '%s'"):format(p, name, o)
      elseif not o and fs.exists(p) then
        problems[#problems + 1] = ("%s: %s exists in filesystem"):format(name, p)
      end
      incoming[p] = name
    end
  end
  return problems
end

-- Install one inspected package archive (it.path, it.pkg).
local function extract(it, idx, total)
  local pi, name = it.pkg.info, it.pkg.info.name
  local old = P.localInfo(name)
  local label = ("(%d/%d) %s %s"):format(idx, total, old and "upgrading" or "installing", name)
  P.progress(label, 0)
  local oldCrc = P.backupCrcs(old)
  local isBackup = {}
  for _, b in ipairs(pi.backup) do isBackup[b] = true end
  local newBackup, notes = {}, {}

  local h = fs.open(it.path, "r")
  local r, e = bpk.open(h)
  if not r then h:close(); return nil, e end
  local done, count = 0, #it.pkg.order
  while true do
    local n, flag, size = r.next()
    if not n then
      if flag then h:close(); return nil, flag end
      break
    end
    if n == ".PKGINFO" or n == ".INSTALL" then
      r.stream(size)
    else
      P.mkdirp(P.parent(n))
      if isBackup[n] then
        local data; data, e = r.read(flag, size)
        if not data then h:close(); return nil, n .. ": " .. e end
        newBackup[#newBackup + 1] = n .. " " .. P.crcOf(data)
        local cur = P.readIf(n)
        if cur == data then
          -- unchanged
        elseif cur == nil or (oldCrc[n] and P.crcOf(cur) == oldCrc[n]) then
          fs.writeAll(n, data)
        else
          fs.writeAll(n .. ".pacnew", data)
          notes[#notes + 1] = n .. " installed as " .. n .. ".pacnew"
        end
      elseif flag == "z" then
        local data; data, e = r.read(flag, size)
        if not data then h:close(); return nil, n .. ": " .. e end
        fs.writeAll(n, data)
      else
        local out = fs.open(n, "w")
        if not out then h:close(); return nil, "cannot write " .. n end
        local ok; ok, e = r.stream(size, function(c) out:write(c) end)
        out:close()
        if not ok then h:close(); return nil, n .. ": " .. e end
      end
      done = done + 1
      P.progress(label, 0.9 * done / count)
    end
  end
  h:close()

  -- files the old version had and the new one does not
  if old then
    for _, p in ipairs(P.localFiles(name)) do
      if not it.pkg.files[p] and fs.exists(p) and not fs.isDirectory(p) then
        if oldCrc[p] and P.crcOf(P.readIf(p)) ~= oldCrc[p] then
          if fs.exists(p .. ".pacsave") then fs.remove(p .. ".pacsave") end
          fs.rename(p, p .. ".pacsave")
          notes[#notes + 1] = p .. " saved as " .. p .. ".pacsave"
        else
          fs.remove(p)
        end
      end
    end
  end

  local dir = LOCAL_DIR .. "/" .. name
  P.mkdirp(dir)
  -- why it is here: named on the command line, or pulled in by another
  -- package; an upgrade keeps what it was (older entries count as explicit)
  local reason = it.reason or (old and old.reason) or "explicit"
  fs.writeAll(dir .. "/desc", bpk.formatInfo({
    name = name, version = pi.version, desc = pi.desc, url = pi.url,
    depend = pi.depend, conflict = pi.conflict, backup = newBackup, isize = pi.isize,
    group = pi.group, optdepend = pi.optdepend, reason = reason,
  }))
  fs.writeAll(dir .. "/files", table.concat(it.pkg.order, "\n") .. "\n")
  if it.pkg.install then
    fs.writeAll(dir .. "/install", it.pkg.install)
  elseif fs.exists(dir .. "/install") then
    fs.remove(dir .. "/install")
  end
  P.progress(label, 1); term.write("\n")
  k.log(old and ("upgraded %s (%s -> %s)"):format(name, tostring(old.version), pi.version)
    or ("installed %s (%s)"):format(name, pi.version), "pacman")

  if old then P.runHook(it.pkg.install, "post_upgrade", pi.version, old.version)
  else P.runHook(it.pkg.install, "post_install", pi.version) end
  for _, note in ipairs(notes) do P.warn(note) end
  return true
end

-- Run a transaction. items: { db = repo package } to download, or
-- { path = local .bpk }. Nothing is written until every package is
-- downloaded, verified and checked for conflicts.
local function commit(items)
  local fetch = {}
  for _, it in ipairs(items) do if it.db then fetch[#fetch + 1] = it end end
  if #fetch > 0 then
    P.header("Retrieving packages...")
    for _, it in ipairs(fetch) do
      local p = it.db
      local label = p.name .. "-" .. p.version
      local csize = tonumber(p.csize) or 0
      local dest = CACHE_DIR .. "/" .. p.filename
      P.progress(label, 0)
      local size, crc = P.download(p.server, p.filename, dest, function(n)
        P.progress(label, csize > 0 and n / csize or 1)
      end)
      if not size then term.write("\n"); P.err("failed retrieving " .. p.filename .. ": " .. crc); return false end
      P.progress(label, 1); term.write("\n")
      if size ~= csize or bpk.hex(crc) ~= p.crc32
          or (p.sha256 and sha256.hex(P.readIf(dest) or "") ~= p.sha256) then
        fs.remove(dest)
        P.err(p.filename .. " is corrupted (size or checksum mismatch); try pacman -Sy")
        return false
      end
      it.path, it.cached = dest, true
    end
  end

  P.info("loading package files...")
  for _, it in ipairs(items) do
    local h = fs.open(it.path, "r")
    if not h then P.err("cannot read " .. it.path); return false end
    local pkg, e = bpk.inspect(h)
    h:close()
    if not pkg then P.err(it.path .. ": " .. e); return false end
    if it.db and (pkg.info.name ~= it.db.name or pkg.info.version ~= it.db.version) then
      P.err(it.path .. " does not match the database entry")
      return false
    end
    it.pkg = pkg
  end

  P.info("checking for file conflicts...")
  local problems = findConflicts(items)
  if #problems > 0 then
    for _, p in ipairs(problems) do P.err(p) end
    P.err("errors occurred, no packages were upgraded.")
    return false
  end

  P.header("Processing package changes...")
  local ok = true
  for i, it in ipairs(items) do
    local done, e = extract(it, i, #items)
    if not done then term.write("\n"); P.err(it.pkg.info.name .. ": " .. tostring(e)); ok = false end
    if it.cached then fs.remove(it.path) end
  end
  return ok
end

local function names(list)
  local out = {}
  for _, p in ipairs(list) do out[#out + 1] = p.name .. "-" .. p.version end
  return out
end

local function sizes(list)
  local dl, ins = 0, 0
  for _, p in ipairs(list) do
    dl = dl + (tonumber(p.csize) or 0)
    ins = ins + (tonumber(p.isize) or 0)
  end
  return dl, ins
end

-- Targets with every group name (that is not also a package) replaced by
-- the group's members.
local function expandGroups(targets)
  if not P.synced() then P.sync() end
  local db, groups, out = P.syncdb(), nil, {}
  for _, t in ipairs(targets) do
    local members
    if not db[P.depName(t)] then
      groups = groups or P.syncGroups()
      members = groups[t]
    end
    if members then
      P.header(("There are %d members in group %s:"):format(#members, t))
      term.cwrite(T.fg, "   " .. table.concat(members, "  ") .. "\n")
      for _, m in ipairs(members) do out[#out + 1] = m end
    else
      out[#out + 1] = t
    end
  end
  return out
end

-- "Optional dependencies for X" with the ones already there marked.
local function showOptional(p)
  if not p.optdepend or #p.optdepend == 0 then return end
  term.cwrite(T.accent, "Optional dependencies for " .. p.name .. "\n")
  for _, o in ipairs(p.optdepend) do
    term.cwrite(T.fg, "    " .. o)
    if P.isInstalled(P.depName(o)) then term.cwrite(T.cyan, " [installed]") end
    term.write("\n")
  end
end

local function install(targets)
  if #targets == 0 then P.err("no targets specified (use -h for help)"); return 1 end
  targets = expandGroups(targets)
  local wantBios, rest = false, {}
  for _, t in ipairs(targets) do
    if t == "bytebios" then wantBios = true else rest[#rest + 1] = t end
  end
  local labels = {}
  if wantBios then
    local st, i = P.biosStatus()
    if st == "unknown" then P.err("bytebios needs a newer byteos; run pacman -Syu first"); return 1 end
    if st == "none" then P.err("this computer has no EEPROM"); return 1 end
    if st == "current" then P.warn("bytebios-" .. i.installed .. " is up to date -- reinstalling") end
    if st == "foreign" then P.info("the current BIOS is kept; pacman -R bytebios puts it back") end
    labels[1] = "bytebios-" .. (i.available or "?")
  end
  local list = {}
  if #rest > 0 then
    P.info("resolving dependencies...")
    list = resolve(rest)
    if not list then return 1 end
    for _, t in ipairs(rest) do
      local i, p = P.localInfo(t), P.syncdb()[t]
      if i and p and bpk.vercmp(i.version, p.version) == 0 then
        P.warn(t .. "-" .. p.version .. " is up to date -- reinstalling")
      end
    end
    P.info("looking for conflicting packages...")
    if not noConflicts(list) then return 1 end
  end
  for _, n in ipairs(names(list)) do labels[#labels + 1] = n end
  local dl, ins = sizes(list)
  if not confirmPackages(labels, "Proceed with installation?", #list > 0 and dl, #list > 0 and ins) then return 1 end
  local ok = true
  if wantBios then
    P.header("Flashing ByteBIOS...")
    ok = P.flashBios()
  end
  if #list > 0 then
    local named = {}
    for _, t in ipairs(rest) do named[P.depName(t)] = true end
    local items = {}
    for _, p in ipairs(list) do
      -- what was asked for is explicit; a new dependency is a dependency
      local reason = named[p.name] and "explicit" or (not P.isInstalled(p.name) and "dependency" or nil)
      items[#items + 1] = { db = p, reason = reason }
    end
    ok = commit(items) and ok
    if ok then for _, p in ipairs(list) do showOptional(p) end end
  end
  return ok and 0 or 1
end

-- -U: install package files; missing dependencies come from the repos.
local function installFiles(paths)
  if #paths == 0 then P.err("no targets specified (use -h for help)"); return 1 end
  local items, provided, labels, missing, ins, infos = {}, {}, {}, {}, 0, {}
  for _, p in ipairs(paths) do
    local path = shell.normalize(p)
    local h = fs.open(path, "r")
    if not h then P.err("'" .. p .. "': file not found"); return 1 end
    local pkg, e = bpk.inspect(h)
    h:close()
    if not pkg then P.err("'" .. p .. "': " .. e); return 1 end
    items[#items + 1] = { path = path, reason = "explicit" }
    infos[#infos + 1] = pkg.info
    provided[pkg.info.name] = pkg.info.version
    labels[#labels + 1] = pkg.info.name .. "-" .. pkg.info.version
    ins = ins + (tonumber(pkg.info.isize) or 0)
    for _, d in ipairs(pkg.info.depend) do missing[#missing + 1] = d end
  end
  P.info("resolving dependencies...")
  local need = {}
  for _, d in ipairs(missing) do
    local dn, op, want = P.parseDep(d)
    if not P.satisfies(provided[dn] or (P.localInfo(dn) or {}).version, op, want) then need[#need + 1] = d end
  end
  local deps = {}
  if #need > 0 then
    deps = resolve(need, provided)
    if not deps then return 1 end
  end
  for _, p in ipairs(deps) do infos[#infos + 1] = p end
  P.info("looking for conflicting packages...")
  if not noConflicts(infos) then return 1 end
  local all = names(deps)
  for _, l in ipairs(labels) do all[#all + 1] = l end
  local dl, dins = sizes(deps)
  if not confirmPackages(all, "Proceed with installation?", dl, ins + dins) then return 1 end
  local tx = {}
  for _, p in ipairs(deps) do tx[#tx + 1] = { db = p } end
  for _, it in ipairs(items) do tx[#tx + 1] = it end
  return commit(tx) and 0 or 1
end

P.resolve = resolve
P.noBreaks = noBreaks
P.confirmPackages = confirmPackages
P.pkgConflicts = pkgConflicts
P.noConflicts = noConflicts
P.findConflicts = findConflicts
P.extract = extract
P.commit = commit
P.names = names
P.sizes = sizes
P.expandGroups = expandGroups
P.showOptional = showOptional
P.install = install
P.installFiles = installFiles
