--[[
  /lib/pacman/query.lua - pacman: the queries: -Q*, -Si, -Sg, -Ss, -Sc and -D

  A part of /bin/pacman.lua, loaded into the same run when one of its
  functions is first needed (see PARTS there); P is shared by all parts.
]]--
local fs, bpk, T = k.fs, require("bpk"), term.theme
local LOCAL_DIR, SYNC_DIR, CACHE_DIR = P.LOCAL_DIR, P.SYNC_DIR, P.CACHE_DIR

-- -Q [pkg...]: installed packages with their versions (only the named ones)
local function queryAll(targets)
  local want, rc = {}, 0
  for _, t in ipairs(targets or {}) do want[t] = true end
  local function show(name, version)
    if next(want) and not want[name] then return end
    want[name] = nil
    term.cwrite(T.bright, name .. " ")
    term.cwrite(T.green, version .. "\n")
  end
  for _, n in ipairs(P.installedNames()) do show(n, P.localInfo(n).version or "?") end
  local st, i = P.biosStatus()
  if st == "current" or st == "outdated" then show("bytebios", i.installed) end
  for n in pairs(want) do P.err("package '" .. n .. "' was not found"); rc = 1 end
  return rc
end

local function row(label, value)
  term.cwrite(T.bright, term.pad(label, 16))
  term.cwrite(T.muted, ": ")
  term.cwrite(T.fg, ((value and value ~= "") and value or "None") .. "\n")
end

-- -Qe, -Qd, -Qt and their mixes (-Qdt: orphans); q: names only
local function queryFiltered(flags, targets)
  local explicit, deps, unneeded, quiet = flags:find("e"), flags:find("d"), flags:find("t"), flags:find("q")
  local want = {}
  for _, t in ipairs(targets) do want[t] = true end
  for _, n in ipairs(P.installedNames()) do
    local i = P.localInfo(n)
    local reason = i.reason or "explicit"
    local keep = (not next(want) or want[n])
      and (not explicit or reason == "explicit")
      and (not deps or reason == "dependency")
      and (not unneeded or #P.requiredBy(n) == 0)
    if keep then
      if quiet then term.write(n .. "\n")
      else term.cwrite(T.bright, n .. " "); term.cwrite(T.green, (i.version or "?") .. "\n") end
    end
  end
  return 0
end

-- -D --asdeps | --asexplicit <pkg>...: change why packages are installed
local function setReason(targets)
  local flag = targets[1]
  local reason = flag == "--asdeps" and "dependency" or flag == "--asexplicit" and "explicit"
  if not reason or #targets < 2 then
    P.err("usage: pacman -D --asdeps|--asexplicit <pkg>..."); return 1
  end
  for i = 2, #targets do
    local name = targets[i]
    local pi = P.localInfo(name)
    if not pi then P.err("package '" .. name .. "' was not found"); return 1 end
    pi.reason = reason
    fs.writeAll(LOCAL_DIR .. "/" .. name .. "/desc", bpk.formatInfo(pi))
    P.info(("%s: install reason has been set to '%s'"):format(name,
      reason == "explicit" and "explicitly installed" or "installed as dependency"))
  end
  return 0
end

-- "Optional Deps" rows: one per suggestion, [installed] where it is
local function optionalRows(i)
  if #i.optdepend == 0 then return row("Optional Deps", nil) end
  for n, o in ipairs(i.optdepend) do
    term.cwrite(T.bright, term.pad(n == 1 and "Optional Deps" or "", 16))
    term.cwrite(T.muted, n == 1 and ": " or "  ")
    term.cwrite(T.fg, o)
    if P.isInstalled(P.depName(o)) then term.cwrite(T.cyan, " [installed]") end
    term.write("\n")
  end
end

-- -Si <pkg>...: what the repositories say about packages
local function syncInfo(targets)
  if #targets == 0 then P.err("no targets specified"); return 1 end
  P.ensureSynced()
  local rc = 0
  for n, name in ipairs(targets) do
    local p = P.syncdb()[name]
    if not p then
      P.notFound(name); rc = 1
    else
      if n > 1 then term.write("\n") end
      row("Repository", p.repo)
      row("Name", p.name)
      row("Version", p.version)
      row("Description", p.desc)
      row("URL", p.url)
      row("Groups", table.concat(p.group, "  "))
      row("Depends On", table.concat(p.depend, "  "))
      optionalRows(p)
      row("Conflicts With", table.concat(p.conflict, "  "))
      row("Download Size", p.csize and P.kib(p.csize))
      row("Installed Size", p.isize and P.kib(p.isize))
    end
  end
  return rc
end

-- -Sg / -Qg [group...]: "group package" lines, for the repositories or
-- for what is installed
local function queryGroups(targets, installedOnly)
  local groups = {}
  if installedOnly then
    for _, n in ipairs(P.installedNames()) do
      for _, g in ipairs(P.localInfo(n).group) do
        groups[g] = groups[g] or {}
        table.insert(groups[g], n)
      end
    end
  else
    P.ensureSynced()
    groups = P.syncGroups()
  end
  local list = targets
  if #list == 0 then
    list = {}
    for g in pairs(groups) do list[#list + 1] = g end
    table.sort(list)
  end
  local rc = 0
  for _, g in ipairs(list) do
    if not groups[g] then P.err("group '" .. g .. "' was not found"); rc = 1
    else
      table.sort(groups[g])
      for _, n in ipairs(groups[g]) do
        term.cwrite(T.bright, g .. " ")
        term.write(n .. "\n")
      end
    end
  end
  return rc
end

local function queryInfo(pkg)
  if not pkg then P.err("no targets specified"); return 1 end
  if pkg == "bytebios" then return P.queryBios() end
  local i = P.localInfo(pkg)
  if not i then P.err("package '" .. pkg .. "' was not found"); return 1 end
  local requiredBy = {}
  for _, n in ipairs(P.installedNames()) do
    for _, d in ipairs(P.localInfo(n).depend) do
      if P.depName(d) == pkg then requiredBy[#requiredBy + 1] = n end
    end
  end
  local backups = {}
  for p in pairs(P.backupCrcs(i)) do backups[#backups + 1] = p end
  table.sort(backups)
  local files = P.localFiles(pkg)
  row("Name", i.name)
  row("Version", i.version)
  row("Description", i.desc)
  row("URL", i.url)
  row("Install Reason", (i.reason or "explicit") == "explicit" and "Explicitly installed"
    or "Installed as a dependency for another package")
  row("Groups", table.concat(i.group, "  "))
  row("Depends On", table.concat(i.depend, "  "))
  optionalRows(i)
  row("Required By", table.concat(requiredBy, "  "))
  row("Conflicts With", table.concat(i.conflict, "  "))
  row("Installed Size", i.isize and P.kib(i.isize))
  row("Backup Files", table.concat(backups, "  "))
  row("Files", tostring(#files))
  for _, f in ipairs(files) do term.cwrite(T.muted, string.rep(" ", 18) .. f .. "\n") end
  return 0
end

-- -Ql [pkg...]: the files of installed packages (all without names)
local function queryFiles(targets)
  local list = #targets > 0 and targets or P.installedNames()
  local rc = 0
  for _, n in ipairs(list) do
    if not P.isInstalled(n) then
      P.err("package '" .. n .. "' was not found"); rc = 1
    else
      for _, f in ipairs(P.localFiles(n)) do
        term.cwrite(T.bright, n .. " ")
        term.write(f .. "\n")
      end
    end
  end
  return rc
end

-- -Qo <file...>: which installed package owns a file
local function queryOwner(paths)
  if #paths == 0 then P.err("no file was specified for --owns"); return 1 end
  local rc = 0
  for _, a in ipairs(paths) do
    local path = shell.normalize(a)
    local owner
    for _, n in ipairs(P.installedNames()) do
      for _, f in ipairs(P.localFiles(n)) do
        if f == path then owner = n break end
      end
      if owner then break end
    end
    if owner then
      term.write(path .. " is owned by ")
      term.cwrite(T.bright, owner .. " ")
      term.cwrite(T.green, (P.localInfo(owner).version or "?") .. "\n")
    else
      P.err("No package owns " .. path); rc = 1
    end
  end
  return rc
end

-- -Sc: empty the package cache (downloads left behind by failed installs)
-- and leftovers of interrupted database syncs.
local function cleanCache()
  local files, bytes = {}, 0
  for _, f in ipairs(fs.list(CACHE_DIR) or {}) do
    if not f:match("/$") then files[#files + 1] = CACHE_DIR .. "/" .. f end
  end
  for _, f in ipairs(fs.list(SYNC_DIR) or {}) do
    if f:match("%.part$") or f:match("%.sig$") or f:match("/$") then
      files[#files + 1] = SYNC_DIR .. "/" .. f:gsub("/$", "")
    end
  end
  for _, f in ipairs(files) do bytes = bytes + (fs.size(f) or 0) end
  P.info("Cache directory: " .. CACHE_DIR .. "/")
  if #files == 0 then P.info(" the cache is already empty"); return 0 end
  if not P.confirm(("Remove %d cached file%s (%s)?"):format(#files, #files == 1 and "" or "s", P.kib(bytes))) then return 1 end
  for _, f in ipairs(files) do fs.remove(f) end
  P.info(" removed " .. #files .. " file" .. (#files == 1 and "" or "s"))
  return 0
end

local function search(pat)
  P.ensureSynced()
  local names_ = P.repoNames()
  for _, repo in ipairs(names_) do
    for _, p in ipairs(bpk.parseDb(P.readIf(SYNC_DIR .. "/" .. repo .. ".db"))) do
      local okn, hitn = pcall(string.find, p.name, pat or "")
      local okd, hitd = pcall(string.find, p.desc or "", pat or "")
      if (okn and hitn) or (okd and hitd) then
        term.cwrite(T.magenta, repo .. "/")
        term.cwrite(T.bright, p.name .. " ")
        term.cwrite(T.green, p.version)
        local i = P.localInfo(p.name)
        if i then
          term.cwrite(T.cyan, i.version == p.version and " [installed]"
            or (" [installed: " .. tostring(i.version) .. "]"))
        end
        term.write("\n")
        term.cwrite(T.fg, "    " .. (p.desc or "") .. "\n")
      end
    end
  end
  return 0
end

P.queryAll = queryAll
P.row = row
P.queryFiltered = queryFiltered
P.setReason = setReason
P.optionalRows = optionalRows
P.syncInfo = syncInfo
P.queryGroups = queryGroups
P.queryInfo = queryInfo
P.queryFiles = queryFiles
P.queryOwner = queryOwner
P.cleanCache = cleanCache
P.search = search
