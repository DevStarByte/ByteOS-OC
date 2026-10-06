--[[
  pacman - ByteOS package manager (Arch-style CLI)

  Operations:
    pacman -S <pkg>...       install packages and their dependencies
    pacman -U <file.bpk>...  install package files from disk
    pacman -R <pkg>...       remove packages
    pacman -Rs <pkg>...      ... and the dependencies nothing else needs
    pacman -Rn <pkg>...      ... and their changed config files (no .pacsave)
    pacman -Rns <pkg>...     both, like on Arch
    pacman -Q                list installed packages
    pacman -Qe / -Qd         only those installed explicitly / as dependencies
    pacman -Qdt              orphans: dependencies nothing needs any more
                             (pacman -Qdtq | pacman -Rns -  removes them;
                             "-" reads the targets from the pipe)
    pacman -Qi <pkg>         show information about an installed package
    pacman -D --asdeps|--asexplicit <pkg>...  change why a package is installed
    pacman -Ss [pattern]     search the repositories
    pacman -Si <pkg>...      show information about repository packages
    pacman -Sg [group]       list package groups and their members
    pacman -Qg [group]       the same for the installed packages
    pacman -S <group>        install every package of a group
    pacman -Sy               synchronize the package databases (-Syy: the same)
    pacman -Syu              upgrade packages and the byteos base system
    pacman --rollback        undo the last byteos upgrade

  Packages are .bpk archives (see /lib/bpk.lua). A repository is the
  Server from pacman.conf, a URL or a directory holding <repo>.db and the
  .bpk files it lists.

  Local database, one directory per installed package:
    /var/lib/pacman/local/<name>/desc     package info; each backup line
                                          also carries the CRC-32 of the
                                          file as shipped ("<path> <crc>");
                                          reason = explicit | dependency
    /var/lib/pacman/local/<name>/files    installed paths, one per line
    /var/lib/pacman/local/<name>/install  the package's hooks, if any
]]--

-- Libraries pacman loads only for itself are let go when it ends, so they
-- do not stay in memory for the rest of the session.
local TRANSIENT = { "bpk", "sha256", "bytebios", "compress", "internet", "sysupgrade" }
local hadLib = {}
for _, n in ipairs(TRANSIENT) do hadLib[n] = package.loaded[n] ~= nil end

local fs   = k.fs
local args = arg or {}
local bpk  = require("bpk")

-- Most of pacman lives in /lib/pacman/<part>.lua: a query never compiles
-- the code for installing, and the other way round. A part is loaded into
-- this run (with this program's term, stdin, ...) the first time one of
-- its functions is used, and goes away with the run. P holds what the
-- parts share: the functions below, and each part's own.
local P = {}
local PARTS = {
  sync = { "download", "b64decode", "verifySignature", "pinServer", "checkSignature", "syncRepo", "sync" },
  install = { "resolve", "noBreaks", "confirmPackages", "pkgConflicts", "noConflicts", "findConflicts", "extract",
              "commit", "names", "sizes", "expandGroups", "showOptional", "install", "installFiles" },
  upgrade = { "baseRepo", "checkBase", "upgradeBase", "upgrade", "rollback" },
  remove = { "held", "removePackage", "requiredBy", "remove" },
  query = { "queryAll", "row", "queryFiltered", "setReason", "optionalRows", "syncInfo", "queryGroups",
            "queryInfo", "queryFiles", "queryOwner", "cleanCache", "search" },
}
local partOf = {}
for part, list in pairs(PARTS) do for _, name in ipairs(list) do partOf[name] = part end end
local partEnv = setmetatable({ P = P }, { __index = _ENV })
setmetatable(P, { __index = function(_, name)
  local part = partOf[name]
  if not part then return nil end
  for _, n in ipairs(PARTS[part]) do partOf[n] = nil end -- each part loads once
  local path = "/lib/pacman/" .. part .. ".lua"
  local src, e = fs.readAll(path)
  if not src then error("pacman: cannot read " .. path .. ": " .. tostring(e), 0) end
  assert(load(src, "=" .. path, "t", partEnv))()
  return rawget(P, name)
end })

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
local FROM_PIPE = false -- the targets came through a pipe ("-")
local function confirm(question)
  term.cwrite(T.accent, ":: ")
  term.cwrite(T.bright, question .. " [Y/n] ")
  if NOCONFIRM then term.write("\n"); return true end
  -- with the targets read from a pipe ("-"), the answer comes from the terminal
  local a = ((FROM_PIPE and require("term").read() or term.read()) or "n"):lower()
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

-- ---- Signatures ------------------------------------------------------------
-- A repo's database may be signed (<repo>.db.sig, ECDSA P-256 + SHA-256 by
-- tools/mkrepo.lua). Checking needs a tier 3 data card; SigLevel in
-- pacman.conf ([options] or per repo) says what happens:
--   Never     signatures are not looked at
--   Optional  checked when a data card is there; unsigned databases pass
--   Required  only correctly signed databases are used
-- (checked in /lib/pacman/sync.lua)

-- The server to fetch repo's packages from: the one its database came
-- from, as long as pacman.conf still names the same Server.
local function packageServer(repo, conf)
  local configured, used = (readIf(SYNC_DIR .. "/" .. repo .. ".db.server") or ""):match("^([^\n]*)\n([^\n]*)")
  if configured == conf.Server and used and used ~= "" then return used end
  return conf.Server
end

local dbs -- name -> repo package info, loaded on first use

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
        p.repo, p.server = repo, packageServer(repo, repos[repo])
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

-- "foo>=1.2" -> "foo", ">=", "1.2"; a plain "foo" has no operator.
local function parseDep(d)
  local name, op, want = d:match("^([^<>=%s]+)%s*([<>=]*)%s*(%S*)$")
  if not name then return d end
  if op == "" or want == "" then return name end
  return name, op, want
end

-- Does `version` meet "op want" (as in foo>=1.2)? No operator: any version.
local function satisfies(version, op, want)
  if not op then return version ~= nil end
  if not version then return false end
  local c = bpk.vercmp(version, want)
  if op == "=" or op == "==" then return c == 0
  elseif op == ">=" then return c >= 0
  elseif op == "<=" then return c <= 0
  elseif op == ">" then return c > 0
  elseif op == "<" then return c < 0 end
  return false
end

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
  k.log("flashed bytebios to the EEPROM", "pacman")
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
  P.row("Name", "bytebios")
  P.row("Version", i.installed)
  P.row("Description", "ByteBIOS bootloader on the EEPROM")
  P.row("Source", "/boot/eeprom.lua" .. (st == "outdated" and " (newer, run pacman -S bytebios)" or ""))
  P.row("Can restore", bios().canRestore() and "yes, pacman -R bytebios" or "no")
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

-- ---- Operations ------------------------------------------------------------
-- name -> sorted member names, for the groups of the repo packages
local function syncGroups()
  local groups = {}
  for name, p in pairs(syncdb()) do
    for _, g in ipairs(p.group or {}) do
      groups[g] = groups[g] or {}
      table.insert(groups[g], name)
    end
  end
  for _, list in pairs(groups) do table.sort(list) end
  return groups
end

-- Queries anyone may run sync first only as root.
local function ensureSynced()
  if synced() then return end
  if k.user() == "root" then
    P.sync()
  else
    warn("the package databases are not synchronized; run sudo pacman -Sy")
  end
end

-- what the parts use from here
P.CONF_PATH, P.LOCAL_DIR, P.SYNC_DIR, P.CACHE_DIR = CONF_PATH, LOCAL_DIR, SYNC_DIR, CACHE_DIR
function P.forgetDb() dbs = nil end -- after a sync
P.ensureDirs = ensureDirs; P.readRepos = readRepos; P.header = header; P.info = info
P.warn = warn; P.err = err; P.progress = progress; P.confirm = confirm; P.kib = kib
P.parent = parent; P.mkdirp = mkdirp; P.readIf = readIf; P.crcOf = crcOf; P.repoNames = repoNames
P.packageServer = packageServer; P.synced = synced; P.syncdb = syncdb; P.localInfo = localInfo
P.localFiles = localFiles; P.installedNames = installedNames; P.isInstalled = isInstalled
P.backupCrcs = backupCrcs; P.depName = depName; P.parseDep = parseDep; P.satisfies = satisfies
P.runHook = runHook; P.bios = bios; P.biosStatus = biosStatus; P.flashBios = flashBios
P.biosHint = biosHint; P.queryBios = queryBios; P.notFound = notFound; P.syncGroups = syncGroups
P.ensureSynced = ensureSynced

-- ===== argument dispatch =====
local function usage()
  term.cwrite(T.bright, "usage: ")
  term.write("pacman <operation> [...]\n")
  term.cwrite(T.bright, "operations:\n")
  local ops = {
    { "-S <pkg>...",  "install packages" },
    { "-U <file>...", "install .bpk package files" },
    { "-R <pkg>...",  "remove packages" },
    { "-Rns <pkg>...", "... with unneeded deps and config" },
    { "-Q",           "list installed packages" },
    { "-Qdt",         "orphans (-Qdtq: names only)" },
    { "-D --asdeps",  "mark as a dependency (--asexplicit)" },
    { "-Qi <pkg>",    "show package information" },
    { "-Ql [pkg]",    "list the files of a package" },
    { "-Qo <file>",   "which package owns a file" },
    { "-Sc",          "clean the package cache" },
    { "-Ss [pattern]", "search the repositories" },
    { "-Si <pkg>",    "show a repository package" },
    { "-Sg [group]",  "list groups and their packages (-Qg: installed)" },
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

-- Arguments and the operation. Run inside main() so the libraries in
-- TRANSIENT are let go however pacman ends.
local function main()
  local rest = {}
  for _, a in ipairs(args) do
    if a == "--noconfirm" then NOCONFIRM = true else rest[#rest + 1] = a end
  end
  local op = rest[1]
  local targets = {}
  for i = 2, #rest do
    if rest[i] == "-" then -- the targets come from the pipe: pacman -Qdtq | pacman -Rns -
      FROM_PIPE = true
      for name in ((stdin and stdin.read("a")) or ""):gmatch("%S+") do targets[#targets + 1] = name end
    else
      targets[#targets + 1] = rest[i]
    end
  end

  -- Everything that changes the system needs root; queries work for anyone.
  local QUERY = { ["-Q"] = true, ["-Qi"] = true, ["-Ql"] = true, ["-Qo"] = true, ["-Ss"] = true,
                  ["-Qg"] = true, ["-Sg"] = true, ["-Si"] = true, ["-h"] = true, ["--help"] = true }
  local qflags = op and op:match("^%-Q([edtq]+)$")
  local rflags = op and op:match("^%-R([ns]*)$")
  if op and not QUERY[op] and not qflags and k.user() ~= "root" then
    err("you cannot perform this operation unless you are root.")
    term.cwrite(T.muted, "  run it with ")
    term.cwrite(T.blue, "sudo pacman " .. table.concat(args, " ") .. "\n")
    return 1
  end
  if k.user() == "root" then ensureDirs() end

  if not op or op == "-h" or op == "--help" then
    usage()
    return op and 0 or 1
  elseif op == "-Syu" or op == "-Su" or op == "-Syyu" then
    return P.upgrade()
  elseif op == "-Sy" or op == "-Syy" then
    if not P.sync() then return 1 end
    if #targets > 0 then return P.install(targets) end
    return 0
  elseif op == "--rollback" then
    return P.rollback()
  elseif op == "-S" then
    return P.install(targets)
  elseif op == "-U" then
    return P.installFiles(targets)
  elseif rflags then
    local opts = { recursive = rflags:find("s") ~= nil, nosave = rflags:find("n") ~= nil }
    local list = {}
    for _, t in ipairs(targets) do
      if t == "--recursive" then opts.recursive = true
      elseif t == "--nosave" then opts.nosave = true
      else list[#list + 1] = t end
    end
    return P.remove(list, opts)
  elseif qflags then
    return P.queryFiltered(qflags, targets)
  elseif op == "-D" then
    return P.setReason(targets)
  elseif op == "-Q" then
    if targets[1] == "-i" or targets[1] == "i" then return P.queryInfo(targets[2]) end
    return P.queryAll(targets)
  elseif op == "-Ql" then
    return P.queryFiles(targets)
  elseif op == "-Qo" then
    return P.queryOwner(targets)
  elseif op == "-Sc" then
    return P.cleanCache()
  elseif op == "-Qi" then
    return P.queryInfo(targets[1])
  elseif op == "-Ss" then
    return P.search(targets[1])
  elseif op == "-Si" then
    return P.syncInfo(targets)
  elseif op == "-Sg" or op == "-Qg" then
    return P.queryGroups(targets, op == "-Qg")
  else
    err("invalid option '" .. op .. "' (use -h for help)"); return 1
  end
  return 0
end

local ok, rc = pcall(main)
for _, n in ipairs(TRANSIENT) do
  if not hadLib[n] then package.loaded[n] = nil end
end
if not ok then error(rc, 0) end
return rc
