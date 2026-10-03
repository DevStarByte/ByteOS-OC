--[[
  pacman - ByteOS package manager (Arch-style CLI)

  Operations:
    pacman -S <pkg>...       install packages and their dependencies
    pacman -U <file.bpk>...  install package files from disk
    pacman -R <pkg>...       remove packages
    pacman -Q                list installed packages
    pacman -Qi <pkg>         show information about an installed package
    pacman -Ss [pattern]     search the repositories
    pacman -Sy               synchronize the package databases
    pacman -Syu              upgrade packages and the byteos base system
    pacman --rollback        undo the last byteos upgrade

  Packages are .bpk archives (see /lib/bpk.lua). A repository is the
  Server from pacman.conf, a URL or a directory holding <repo>.db and the
  .bpk files it lists.

  Local database, one directory per installed package:
    /var/lib/pacman/local/<name>/desc     package info; each backup line
                                          also carries the CRC-32 of the
                                          file as shipped ("<path> <crc>")
    /var/lib/pacman/local/<name>/files    installed paths, one per line
    /var/lib/pacman/local/<name>/install  the package's hooks, if any
]]--

local fs   = k.fs
local args = arg or {}
local bpk  = require("bpk")

local CONF_PATH = "/etc/pacman.conf"
local LOCAL_DIR = "/var/lib/pacman/local"
local SYNC_DIR  = "/var/lib/pacman/sync"
local CACHE_DIR = "/var/cache/pacman/pkg"

local function ensureDirs()
  for _, d in ipairs({ LOCAL_DIR, SYNC_DIR, CACHE_DIR }) do
    if not fs.exists(d) then fs.makeDirectory(d) end
  end
end

local function readRepos()
  local repos = {}
  if not fs.exists(CONF_PATH) then return repos end
  local section
  for raw in (fs.readAll(CONF_PATH) or ""):gmatch("[^\n]+") do
    local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if line:sub(1,1) == "#" or line == "" then
      -- comment/blank
    elseif line:sub(1,1) == "[" then
      section = line:match("%[(.-)%]")
      repos[section] = repos[section] or {}
    elseif section then
      local k_, v = line:match("^([^=]-)%s*=%s*(.+)$")
      if k_ then repos[section][k_] = v end
    end
  end
  return repos
end

local T = term.theme
local W = term.size()

-- pacman-style message helpers
local function header(msg)          -- ":: Synchronizing package databases..."
  term.cwrite(T.accent, ":: ")
  term.cwrite(T.bright, msg .. "\n")
end
local function info(msg) term.cwrite(T.fg, msg .. "\n") end
local function warn(msg)
  term.cwrite(T.warn, "warning: ")
  term.cwrite(T.fg, msg .. "\n")
end
local function err(msg)
  term.cwrite(T.err, "error: ")
  term.cwrite(T.fg, msg .. "\n")
end

-- A full-width progress line: " label            [#########-----] 100%"
local function progress(label, frac)
  local barW = math.max(10, math.min(30, W - 30))
  local labelW = W - barW - 9
  local _, y = term.getCursor()
  term.setCursor(1, y)
  term.cwrite(T.fg, term.pad(term.usub(" " .. label, 1, labelW), labelW))
  local filled = math.floor(barW * math.min(1, frac) + 0.5)
  term.cwrite(T.muted, " [")
  term.cwrite(T.accent, string.rep("#", filled))
  term.cwrite(T.dim, string.rep("-", barW - filled))
  term.cwrite(T.muted, "]")
  term.cwrite(T.fg, ("%4d%%"):format(math.floor(math.min(1, frac) * 100 + 0.5)))
end

local NOCONFIRM = false
local function confirm(question)
  term.cwrite(T.accent, ":: ")
  term.cwrite(T.bright, question .. " [Y/n] ")
  if NOCONFIRM then term.write("\n"); return true end
  local a = (term.read() or "n"):lower()
  return a == "" or a == "y" or a == "yes"
end

local function kib(n) return ("%.1f KiB"):format((tonumber(n) or 0) / 1024) end
local function parent(p) return p:match("^(.*)/[^/]*$") or "" end
local function mkdirp(d)
  if d ~= "" and not fs.exists(d) then fs.makeDirectory(d) end
end
local function readIf(p)
  if fs.exists(p) then return fs.readAll(p) end
end
local function crcOf(data) return bpk.hex(bpk.crc32(data or "")) end

-- ---- Repositories ----------------------------------------------------------
local function repoNames()
  local repos, names = readRepos(), {}
  for name, conf in pairs(repos) do if conf.Server then names[#names + 1] = name end end
  table.sort(names)
  return names, repos
end

-- Copy <server>/<name> into the file `dest`. A server is a URL (through the
-- internet card) or a directory. Returns size, crc32 or nil, reason.
local function download(server, name, dest, onBytes)
  local src = server .. "/" .. name
  local out = fs.open(dest, "w")
  if not out then return nil, "cannot write " .. dest end
  local size, crc = 0, 0
  local function sink(c)
    out:write(c)
    size = size + #c
    crc = bpk.crc32(c, crc)
    if onBytes then onBytes(size) end
  end
  local ok, e
  if src:match("^https?://") then
    local internet = require("internet")
    if internet.available() then ok, e = internet.get(src, sink)
    else ok, e = nil, "no internet card" end
  elseif fs.exists(src) then
    local h = fs.open(src, "r")
    while true do
      local c = h:read(4096)
      if not c then break end
      sink(c)
    end
    h:close()
    ok = true
  else
    ok, e = nil, "not found"
  end
  out:close()
  if not ok then fs.remove(dest); return nil, tostring(e) .. " (" .. src .. ")" end
  return size, crc
end

local function syncRepo(name, conf)
  local dest = SYNC_DIR .. "/" .. name .. ".db"
  -- databases from before .bpk lived in <sync>/<repo>/repo.db
  if fs.isDirectory(SYNC_DIR .. "/" .. name) then fs.remove(SYNC_DIR .. "/" .. name) end
  local size, e = download(conf.Server, name .. ".db", dest .. ".part")
  if not size then
    err("failed to synchronize " .. name .. ": " .. e)
    return false
  end
  if readIf(dest) == readIf(dest .. ".part") then
    fs.remove(dest .. ".part")
    term.cwrite(T.fg, " " .. name)
    term.cwrite(T.muted, " is up to date\n")
  else
    if fs.exists(dest) then fs.remove(dest) end
    fs.rename(dest .. ".part", dest)
    progress(name, 1); term.write("\n")
  end
  return true
end

local dbs -- name -> repo package info, loaded on first use

local function sync()
  header("Synchronizing package databases...")
  local names, repos = repoNames()
  local ok = #names > 0
  for _, name in ipairs(names) do ok = syncRepo(name, repos[name]) and ok end
  dbs = nil
  if not ok then
    -- the usual cause: an old pacman.conf that -Syu kept next to a new one
    if fs.exists(CONF_PATH .. ".new") then
      warn("a newer config was saved as " .. CONF_PATH .. ".new; to use it run")
      term.cwrite(T.blue, "    mv " .. CONF_PATH .. ".new " .. CONF_PATH .. "\n")
    else
      warn("check the Server lines in " .. CONF_PATH)
    end
  end
  return ok
end

-- True once every configured repo has a synced database.
local function synced()
  for _, name in ipairs((repoNames())) do
    if not fs.exists(SYNC_DIR .. "/" .. name .. ".db") then return false end
  end
  return true
end

-- All repo packages by name; the first repo (alphabetically) wins.
local function syncdb()
  if dbs then return dbs end
  dbs = {}
  local names, repos = repoNames()
  for _, repo in ipairs(names) do
    for _, p in ipairs(bpk.parseDb(readIf(SYNC_DIR .. "/" .. repo .. ".db"))) do
      if not dbs[p.name] then
        p.repo, p.server = repo, repos[repo].Server
        dbs[p.name] = p
      end
    end
  end
  return dbs
end

-- ---- Local database --------------------------------------------------------
local function localInfo(name)
  local d = readIf(LOCAL_DIR .. "/" .. name .. "/desc")
  if not d then return nil end
  local i = bpk.parseInfo(d)
  i.name = i.name or name
  return i
end

local function localFiles(name)
  local out = {}
  for f in (readIf(LOCAL_DIR .. "/" .. name .. "/files") or ""):gmatch("[^\r\n]+") do
    out[#out + 1] = f
  end
  return out
end

local function installedNames()
  local out = {}
  for _, e_ in ipairs(fs.list(LOCAL_DIR) or {}) do
    local n = e_:gsub("/$", "")
    if fs.exists(LOCAL_DIR .. "/" .. n .. "/desc") then out[#out + 1] = n end
  end
  table.sort(out)
  return out
end

local function isInstalled(name) return fs.exists(LOCAL_DIR .. "/" .. name .. "/desc") end

-- backup lines in the local db: "<path> <crc32 as shipped>"
local function backupCrcs(i)
  local out = {}
  for _, b in ipairs(i and i.backup or {}) do
    local p, c = b:match("^(%S+)%s*(%x*)$")
    if p then out[p] = c end
  end
  return out
end

local function depName(d) return d:match("^[^<>=%s]+") end

-- Run hook `fn` from a package's install script, if it defines one.
local function runHook(code, fn, ...)
  if not code then return end
  local env = setmetatable({ fs = fs, term = term, k = k, shell = shell }, { __index = _G })
  local chunk, e = load(code, "=.INSTALL", "t", env)
  if not chunk then warn("install script: " .. tostring(e)); return end
  local ok, e2 = pcall(chunk)
  if not ok then warn("install script: " .. tostring(e2)); return end
  if type(env[fn]) == "function" then
    local ok3, e3 = pcall(env[fn], ...)
    if not ok3 then warn(fn .. " failed: " .. tostring(e3)) end
  end
end

-- ---- ByteBIOS --------------------------------------------------------------
-- "bytebios" is ByteBIOS on the EEPROM (see /lib/bytebios.lua). The library
-- arrives with byteos, so a system that was not upgraded yet may lack it.
local function bios()
  local ok, mod = pcall(require, "bytebios")
  return ok and mod or nil
end

local function biosStatus()
  local b = bios()
  if not b then return "unknown", {} end
  return b.status()
end

local function flashBios()
  local label = "flashing bytebios to the EEPROM"
  progress(label, 0)
  local ok, e = bios().flash()
  if not ok then term.write("\n"); err("bytebios: " .. e); return false end
  progress(label, 1); term.write("\n")
  return true
end

local function biosHint()
  term.cwrite(T.muted, " ByteBIOS is not on the EEPROM yet; install it with ")
  term.cwrite(T.blue, "pacman -S bytebios\n")
end

local function queryBios()
  local st, i = biosStatus()
  if st ~= "current" and st ~= "outdated" then err("package 'bytebios' was not found"); return end
  local function row(label, value)
    term.cwrite(T.bright, term.pad(label, 14))
    term.cwrite(T.muted, ": ")
    term.cwrite(T.fg, (value or "None") .. "\n")
  end
  row("Name", "bytebios")
  row("Version", i.installed)
  row("Description", "ByteBIOS bootloader on the EEPROM")
  row("Source", "/boot/eeprom.lua" .. (st == "outdated" and " (newer, run pacman -S bytebios)" or ""))
  row("Can restore", bios().canRestore() and "yes, pacman -R bytebios" or "no")
end

-- ---- Resolving -------------------------------------------------------------
local function notFound(name, by)
  err("target not found: " .. name .. (by and (" (required by " .. by .. ")") or ""))
  if not synced() then
    term.cwrite(T.muted, "  the package databases could not be synchronized (see above)\n")
  else
    term.cwrite(T.muted, "  try ")
    term.cwrite(T.blue, "pacman -Sy")
    term.cwrite(T.muted, " to refresh, or ")
    term.cwrite(T.blue, "pacman -Ss " .. name)
    term.cwrite(T.muted, " to search\n")
  end
end

-- Repo packages for `targets` plus every dependency that is not installed
-- yet, dependencies first. `provided` names count as installed. Returns
-- the list, or nil after printing why.
local function resolve(targets, provided)
  if not synced() then sync() end
  local db = syncdb()
  local order, seen = {}, {}
  local function visit(name, by)
    if seen[name] then return true end
    seen[name] = true
    local p = db[name]
    if not p then notFound(name, by); return false end
    for _, d in ipairs(p.depend) do
      local dn = depName(d)
      if dn and not isInstalled(dn) and not (provided and provided[dn]) then
        if not visit(dn, name) then return false end
      end
    end
    order[#order + 1] = p
    return true
  end
  for _, t in ipairs(targets) do
    if not visit(t) then return nil end
  end
  return order
end

-- "Packages (2) foo-1.0  bar-2.0", sizes, then the confirmation prompt.
local function confirmPackages(names, question, dlSize, inSize)
  term.write("\n")
  term.cwrite(T.bright, ("Packages (%d) "):format(#names))
  term.cwrite(T.fg, table.concat(names, "  ") .. "\n\n")
  if dlSize and dlSize > 0 then
    term.cwrite(T.bright, "Total Download Size:   ")
    term.cwrite(T.fg, kib(dlSize) .. "\n")
  end
  if inSize then
    term.cwrite(T.bright, "Total Installed Size:  ")
    term.cwrite(T.fg, kib(inSize) .. "\n")
  end
  if dlSize or inSize then term.write("\n") end
  return confirm(question)
end

-- ---- Transactions ----------------------------------------------------------
-- Conflicts between the packages `infos` (about to be installed) and the
-- installed packages or each other. The repo database has everything this
-- needs, so it runs before the confirmation prompt.
local function pkgConflicts(infos)
  local problems, names = {}, {}
  for _, p in ipairs(infos) do names[p.name] = true end
  for _, p in ipairs(infos) do
    for _, c in ipairs(p.conflict or {}) do
      local cn = depName(c)
      if cn and cn ~= p.name and (isInstalled(cn) or names[cn]) then
        problems[#problems + 1] = ("%s and %s are in conflict"):format(p.name, cn)
      end
    end
    for _, n in ipairs(installedNames()) do
      if n ~= p.name and not names[n] then
        for _, c in ipairs((localInfo(n) or {}).conflict or {}) do
          if depName(c) == p.name then
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
  for _, p in ipairs(problems) do err(p) end
  if #problems > 0 then err("unresolvable package conflicts detected") end
  return #problems == 0
end

-- Every problem that stops the transaction, checked before anything is
-- written: package conflicts and files another package (or the base
-- system) owns or that already exist on disk.
local function findConflicts(items)
  local infos = {}
  for _, it in ipairs(items) do infos[#infos + 1] = it.pkg.info end
  local problems = pkgConflicts(infos)
  local owner = {}
  for _, n in ipairs(installedNames()) do
    for _, f in ipairs(localFiles(n)) do owner[f] = n end
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
  local old = localInfo(name)
  local label = ("(%d/%d) %s %s"):format(idx, total, old and "upgrading" or "installing", name)
  progress(label, 0)
  local oldCrc = backupCrcs(old)
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
      mkdirp(parent(n))
      if isBackup[n] then
        local data; data, e = r.read(flag, size)
        if not data then h:close(); return nil, n .. ": " .. e end
        newBackup[#newBackup + 1] = n .. " " .. crcOf(data)
        local cur = readIf(n)
        if cur == data then
          -- unchanged
        elseif cur == nil or (oldCrc[n] and crcOf(cur) == oldCrc[n]) then
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
      progress(label, 0.9 * done / count)
    end
  end
  h:close()

  -- files the old version had and the new one does not
  if old then
    for _, p in ipairs(localFiles(name)) do
      if not it.pkg.files[p] and fs.exists(p) and not fs.isDirectory(p) then
        if oldCrc[p] and crcOf(readIf(p)) ~= oldCrc[p] then
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
  mkdirp(dir)
  fs.writeAll(dir .. "/desc", bpk.formatInfo({
    name = name, version = pi.version, desc = pi.desc, url = pi.url,
    depend = pi.depend, conflict = pi.conflict, backup = newBackup, isize = pi.isize,
  }))
  fs.writeAll(dir .. "/files", table.concat(it.pkg.order, "\n") .. "\n")
  if it.pkg.install then
    fs.writeAll(dir .. "/install", it.pkg.install)
  elseif fs.exists(dir .. "/install") then
    fs.remove(dir .. "/install")
  end
  progress(label, 1); term.write("\n")

  if old then runHook(it.pkg.install, "post_upgrade", pi.version, old.version)
  else runHook(it.pkg.install, "post_install", pi.version) end
  for _, note in ipairs(notes) do warn(note) end
  return true
end

-- Run a transaction. items: { db = repo package } to download, or
-- { path = local .bpk }. Nothing is written until every package is
-- downloaded, verified and checked for conflicts.
local function commit(items)
  local fetch = {}
  for _, it in ipairs(items) do if it.db then fetch[#fetch + 1] = it end end
  if #fetch > 0 then
    header("Retrieving packages...")
    for _, it in ipairs(fetch) do
      local p = it.db
      local label = p.name .. "-" .. p.version
      local csize = tonumber(p.csize) or 0
      local dest = CACHE_DIR .. "/" .. p.filename
      progress(label, 0)
      local size, crc = download(p.server, p.filename, dest, function(n)
        progress(label, csize > 0 and n / csize or 1)
      end)
      if not size then term.write("\n"); err("failed retrieving " .. p.filename .. ": " .. crc); return false end
      progress(label, 1); term.write("\n")
      if size ~= csize or bpk.hex(crc) ~= p.crc32 then
        fs.remove(dest)
        err(p.filename .. " is corrupted (size or checksum mismatch); try pacman -Sy")
        return false
      end
      it.path, it.cached = dest, true
    end
  end

  info("loading package files...")
  for _, it in ipairs(items) do
    local h = fs.open(it.path, "r")
    if not h then err("cannot read " .. it.path); return false end
    local pkg, e = bpk.inspect(h)
    h:close()
    if not pkg then err(it.path .. ": " .. e); return false end
    if it.db and (pkg.info.name ~= it.db.name or pkg.info.version ~= it.db.version) then
      err(it.path .. " does not match the database entry")
      return false
    end
    it.pkg = pkg
  end

  info("checking for file conflicts...")
  local problems = findConflicts(items)
  if #problems > 0 then
    for _, p in ipairs(problems) do err(p) end
    err("errors occurred, no packages were upgraded.")
    return false
  end

  header("Processing package changes...")
  local ok = true
  for i, it in ipairs(items) do
    local done, e = extract(it, i, #items)
    if not done then term.write("\n"); err(it.pkg.info.name .. ": " .. tostring(e)); ok = false end
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

-- ---- Operations ------------------------------------------------------------
local function install(targets)
  if #targets == 0 then err("no targets specified (use -h for help)"); return 1 end
  local wantBios, rest = false, {}
  for _, t in ipairs(targets) do
    if t == "bytebios" then wantBios = true else rest[#rest + 1] = t end
  end
  local labels = {}
  if wantBios then
    local st, i = biosStatus()
    if st == "unknown" then err("bytebios needs a newer byteos; run pacman -Syu first"); return 1 end
    if st == "none" then err("this computer has no EEPROM"); return 1 end
    if st == "current" then warn("bytebios-" .. i.installed .. " is up to date -- reinstalling") end
    if st == "foreign" then info("the current BIOS is kept; pacman -R bytebios puts it back") end
    labels[1] = "bytebios-" .. (i.available or "?")
  end
  local list = {}
  if #rest > 0 then
    info("resolving dependencies...")
    list = resolve(rest)
    if not list then return 1 end
    for _, t in ipairs(rest) do
      local i, p = localInfo(t), syncdb()[t]
      if i and p and bpk.vercmp(i.version, p.version) == 0 then
        warn(t .. "-" .. p.version .. " is up to date -- reinstalling")
      end
    end
    info("looking for conflicting packages...")
    if not noConflicts(list) then return 1 end
  end
  for _, n in ipairs(names(list)) do labels[#labels + 1] = n end
  local dl, ins = sizes(list)
  if not confirmPackages(labels, "Proceed with installation?", #list > 0 and dl, #list > 0 and ins) then return 1 end
  local ok = true
  if wantBios then
    header("Flashing ByteBIOS...")
    ok = flashBios()
  end
  if #list > 0 then
    local items = {}
    for _, p in ipairs(list) do items[#items + 1] = { db = p } end
    ok = commit(items) and ok
  end
  return ok and 0 or 1
end

-- -U: install package files; missing dependencies come from the repos.
local function installFiles(paths)
  if #paths == 0 then err("no targets specified (use -h for help)"); return 1 end
  local items, provided, labels, missing, ins, infos = {}, {}, {}, {}, 0, {}
  for _, p in ipairs(paths) do
    local path = shell.normalize(p)
    local h = fs.open(path, "r")
    if not h then err("'" .. p .. "': file not found"); return 1 end
    local pkg, e = bpk.inspect(h)
    h:close()
    if not pkg then err("'" .. p .. "': " .. e); return 1 end
    items[#items + 1] = { path = path }
    infos[#infos + 1] = pkg.info
    provided[pkg.info.name] = true
    labels[#labels + 1] = pkg.info.name .. "-" .. pkg.info.version
    ins = ins + (tonumber(pkg.info.isize) or 0)
    for _, d in ipairs(pkg.info.depend) do missing[#missing + 1] = depName(d) end
  end
  info("resolving dependencies...")
  local need = {}
  for _, d in ipairs(missing) do
    if d and not isInstalled(d) and not provided[d] then need[#need + 1] = d end
  end
  local deps = {}
  if #need > 0 then
    deps = resolve(need, provided)
    if not deps then return 1 end
  end
  for _, p in ipairs(deps) do infos[#infos + 1] = p end
  info("looking for conflicting packages...")
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

-- ---- Base system -----------------------------------------------------------
-- The OS itself is the "byteos" package. It is in no repo database: pacman
-- upgrades it file by file from the git repository named in pacman.conf.
local function baseRepo()
  local o = readRepos().options or {}
  return o.BaseRepo or "DevStarByte/ByteOS-OC", o.BaseBranch or "master"
end

-- Returns the pending base upgrade, or nil if there is none / it cannot
-- be checked right now (the reason is printed).
local function checkBase()
  if not require("internet").available() then
    info(" no internet card: skipping the byteos base system")
    return nil
  end
  local repo, branch = baseRepo()
  local up, e = require("sysupgrade").check(repo, branch)
  if not up then warn("cannot check byteos for updates: " .. e); return nil end
  if up.uptodate then return nil end
  return up
end

local function upgradeBase(up)
  local sysupgrade = require("sysupgrade")
  header("Retrieving byteos " .. up.version .. " from " .. up.repo .. "...")
  local ok, e = sysupgrade.download(up, progress)
  if not ok then
    term.write("\n")
    err("failed to retrieve byteos: " .. e)
    info("the base system was not changed")
    return false
  end
  progress(("downloaded %d file%s"):format(up.downloaded, up.downloaded == 1 and "" or "s"), 1)
  term.write("\n")
  header("Upgrading byteos...")
  ok, e = sysupgrade.apply(up, function(label, frac) progress("upgrading " .. label, frac) end)
  if not ok then term.write("\n"); err(e); return false end
  progress(("upgraded byteos to %s"):format(up.version), 1)
  term.write("\n")
  for _, path in ipairs(up.pacnew) do
    warn(path .. " installed as " .. path .. ".new")
  end
  return true
end

local function upgrade()
  sync()
  header("Starting full system upgrade...")
  local base = checkBase()
  local db, outdated = syncdb(), {}
  for _, n in ipairs(installedNames()) do
    local i, p = localInfo(n), db[n]
    if p and i and bpk.vercmp(p.version, i.version or "0") > 0 then outdated[#outdated + 1] = n end
  end
  local list = {}
  if #outdated > 0 then
    list = resolve(outdated)
    if not list or not noConflicts(list) then return 1 end
  end
  -- ByteBIOS is only reflashed if it is already on the EEPROM; another
  -- BIOS is never replaced without an explicit `pacman -S bytebios`.
  local biosState, biosInfo = biosStatus()
  local biosNow = not base and biosState == "outdated"
  if not base and #list == 0 and not biosNow then
    info(" there is nothing to do")
    if biosState == "foreign" then biosHint() end
    return 0
  end

  local labels = {}
  if base then labels[1] = "byteos-" .. base.version end
  if biosNow then labels[#labels + 1] = "bytebios-" .. (biosInfo.available or "?") end
  for _, n in ipairs(names(list)) do labels[#labels + 1] = n end
  local dl = sizes(list)
  if not confirmPackages(labels, "Proceed with installation?", dl) then return 1 end

  local ok = true
  if base then
    ok = upgradeBase(base)
    -- the upgrade may have brought a new /boot/eeprom.lua
    if ok and biosState ~= "foreign" and biosStatus() == "outdated" then biosNow = true end
  end
  if ok and biosNow then
    header("Updating ByteBIOS on the EEPROM...")
    ok = flashBios()
  end
  if ok and #list > 0 then
    local items = {}
    for _, p in ipairs(list) do items[#items + 1] = { db = p } end
    ok = commit(items)
  end
  if base and ok then
    term.cwrite(T.accent, ":: ")
    term.cwrite(T.bright, "byteos was upgraded; reboot to start the new version\n")
  end
  if ok and biosState == "foreign" then biosHint() end
  return ok and 0 or 1
end

local function rollback()
  local sysupgrade = require("sysupgrade")
  if not sysupgrade.canRollback() then err("there is no byteos upgrade to roll back"); return 1 end
  if not confirm("Restore byteos from before the last upgrade?") then return 1 end
  sysupgrade.rollback()
  info("previous byteos restored; reboot to use it")
  return 0
end

-- Packages that -R refuses to remove (HoldPkg in pacman.conf).
local function held()
  local set = { byteos = true }
  for n in ((readRepos().options or {}).HoldPkg or ""):gmatch("%S+") do set[n] = true end
  return set
end

local function removePackage(name, idx, total)
  local label = ("(%d/%d) removing %s"):format(idx, total, name)
  progress(label, 0)
  local i = localInfo(name)
  local hooks = readIf(LOCAL_DIR .. "/" .. name .. "/install")
  runHook(hooks, "pre_remove", i.version)
  local crcs, notes = backupCrcs(i), {}
  for _, f in ipairs(localFiles(name)) do
    if fs.exists(f) and not fs.isDirectory(f) then
      if crcs[f] and crcOf(readIf(f)) ~= crcs[f] then
        if fs.exists(f .. ".pacsave") then fs.remove(f .. ".pacsave") end
        fs.rename(f, f .. ".pacsave")
        notes[#notes + 1] = f .. " saved as " .. f .. ".pacsave"
      else
        fs.remove(f)
      end
    end
  end
  fs.remove(LOCAL_DIR .. "/" .. name)
  progress(label, 1); term.write("\n")
  runHook(hooks, "post_remove", i.version)
  for _, note in ipairs(notes) do warn(note) end
end

local function remove(targets)
  if #targets == 0 then err("no targets specified (use -h for help)"); return 1 end
  local hold, set, labels = held(), {}, {}
  for _, t in ipairs(targets) do set[t] = true end
  for _, pkg in ipairs(targets) do
    if pkg == "bytebios" then
      local st, i = biosStatus()
      if st ~= "current" and st ~= "outdated" then err("target not found: bytebios"); return 1 end
      if not bios().canRestore() then
        err("the BIOS from before ByteBIOS was not saved, so bytebios cannot be removed")
        return 1
      end
      labels[#labels + 1] = "bytebios-" .. i.installed
    elseif not isInstalled(pkg) then
      err("target not found: " .. pkg); return 1
    elseif hold[pkg] then
      err(pkg .. " is part of the base system and cannot be removed (HoldPkg)")
      return 1
    else
      labels[#labels + 1] = pkg .. "-" .. (localInfo(pkg).version or "?")
    end
  end
  info("checking dependencies...")
  local broken = false
  for _, n in ipairs(installedNames()) do
    if not set[n] then
      for _, d in ipairs(localInfo(n).depend) do
        if set[depName(d)] then
          err(("removing %s breaks dependency '%s' required by %s"):format(depName(d), d, n))
          broken = true
        end
      end
    end
  end
  if broken then return 1 end
  if not confirmPackages(labels, "Do you want to remove these packages?") then return 1 end
  header("Processing package changes...")
  local ok = true
  for i, pkg in ipairs(targets) do
    if pkg == "bytebios" then
      local label = ("(%d/%d) restoring the previous BIOS"):format(i, #targets)
      progress(label, 0)
      local done, e = bios().restore()
      if done then progress(label, 1); term.write("\n")
      else term.write("\n"); err("bytebios: " .. e); ok = false end
    else
      removePackage(pkg, i, #targets)
    end
  end
  return ok and 0 or 1
end

local function queryAll()
  for _, n in ipairs(installedNames()) do
    term.cwrite(T.bright, n .. " ")
    term.cwrite(T.green, (localInfo(n).version or "?") .. "\n")
  end
  local st, i = biosStatus()
  if st == "current" or st == "outdated" then
    term.cwrite(T.bright, "bytebios ")
    term.cwrite(T.green, i.installed .. "\n")
  end
end

local function row(label, value)
  term.cwrite(T.bright, term.pad(label, 16))
  term.cwrite(T.muted, ": ")
  term.cwrite(T.fg, ((value and value ~= "") and value or "None") .. "\n")
end

local function queryInfo(pkg)
  if not pkg then err("no targets specified"); return 1 end
  if pkg == "bytebios" then return queryBios() end
  local i = localInfo(pkg)
  if not i then err("package '" .. pkg .. "' was not found"); return 1 end
  local requiredBy = {}
  for _, n in ipairs(installedNames()) do
    for _, d in ipairs(localInfo(n).depend) do
      if depName(d) == pkg then requiredBy[#requiredBy + 1] = n end
    end
  end
  local backups = {}
  for p in pairs(backupCrcs(i)) do backups[#backups + 1] = p end
  table.sort(backups)
  local files = localFiles(pkg)
  row("Name", i.name)
  row("Version", i.version)
  row("Description", i.desc)
  row("URL", i.url)
  row("Depends On", table.concat(i.depend, "  "))
  row("Required By", table.concat(requiredBy, "  "))
  row("Conflicts With", table.concat(i.conflict, "  "))
  row("Installed Size", i.isize and kib(i.isize))
  row("Backup Files", table.concat(backups, "  "))
  row("Files", tostring(#files))
  for _, f in ipairs(files) do term.cwrite(T.muted, string.rep(" ", 18) .. f .. "\n") end
  return 0
end

local function search(pat)
  if not synced() then
    if k.user() == "root" then
      sync()
    else
      warn("the package databases are not synchronized; run sudo pacman -Sy")
    end
  end
  local names_ = repoNames()
  for _, repo in ipairs(names_) do
    for _, p in ipairs(bpk.parseDb(readIf(SYNC_DIR .. "/" .. repo .. ".db"))) do
      local okn, hitn = pcall(string.find, p.name, pat or "")
      local okd, hitd = pcall(string.find, p.desc or "", pat or "")
      if (okn and hitn) or (okd and hitd) then
        term.cwrite(T.magenta, repo .. "/")
        term.cwrite(T.bright, p.name .. " ")
        term.cwrite(T.green, p.version)
        local i = localInfo(p.name)
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

-- ===== argument dispatch =====
local function usage()
  term.cwrite(T.bright, "usage: ")
  term.write("pacman <operation> [...]\n")
  term.cwrite(T.bright, "operations:\n")
  local ops = {
    { "-S <pkg>...",  "install packages" },
    { "-U <file>...", "install .bpk package files" },
    { "-R <pkg>...",  "remove packages" },
    { "-Q",           "list installed packages" },
    { "-Qi <pkg>",    "show package information" },
    { "-Ss [pattern]", "search the repositories" },
    { "-Sy",          "synchronize package databases" },
    { "-Syu",         "upgrade packages and the byteos base system" },
    { "--rollback",   "undo the last byteos upgrade" },
    { "-S bytebios",  "flash ByteBIOS to the EEPROM" },
  }
  for _, o in ipairs(ops) do
    term.cwrite(T.green, "    " .. term.pad(o[1], 15))
    term.cwrite(T.fg, o[2] .. "\n")
  end
  term.cwrite(T.muted, "options: --noconfirm  do not ask for confirmation\n")
end

local rest = {}
for _, a in ipairs(args) do
  if a == "--noconfirm" then NOCONFIRM = true else rest[#rest + 1] = a end
end
local op = rest[1]
local targets = { table.unpack(rest, 2) }

-- Everything that changes the system needs root; queries work for anyone.
local QUERY = { ["-Q"] = true, ["-Qi"] = true, ["-Ss"] = true, ["-h"] = true, ["--help"] = true }
if op and not QUERY[op] and k.user() ~= "root" then
  err("you cannot perform this operation unless you are root.")
  term.cwrite(T.muted, "  run it with ")
  term.cwrite(T.blue, "sudo pacman " .. table.concat(args, " ") .. "\n")
  return 1
end
if k.user() == "root" then ensureDirs() end

if not op or op == "-h" or op == "--help" then
  usage()
  return op and 0 or 1
elseif op == "-Syu" or op == "-Su" then
  return upgrade()
elseif op == "-Sy" then
  if not sync() then return 1 end
  if #targets > 0 then return install(targets) end
  return 0
elseif op == "--rollback" then
  return rollback()
elseif op == "-S" then
  return install(targets)
elseif op == "-U" then
  return installFiles(targets)
elseif op == "-R" then
  return remove(targets)
elseif op == "-Q" then
  if targets[1] == "-i" or targets[1] == "i" then return queryInfo(targets[2]) end
  queryAll()
elseif op == "-Qi" then
  return queryInfo(targets[1])
elseif op == "-Ss" then
  return search(targets[1])
else
  err("invalid option '" .. op .. "' (use -h for help)"); return 1
end
return 0
