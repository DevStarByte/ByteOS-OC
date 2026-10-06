--[[
  /boot/kernel.lua - ByteOS kernel
  Provides:
    * event loop (signals)
    * process scheduler (cooperative)
    * VFS (mount table over component filesystems)
    * package loader (require)
    * core kernel API in _G.kernel
]]--

local component = component
local computer  = computer

local kernel = {}
_G.kernel = kernel

-- ============================================================
-- Event/Signal subsystem
-- ============================================================
local listeners = {}
local ctrlHeld = false

-- The background processes (see "Processes" below); declared here
-- because waiting for signals is what lets them run.
local procs = {}        -- pid -> process
local currentProc       -- the process being resumed right now, if any
local runProcesses      -- function(sig): give the processes their turn
local INTERRUPT = {}    -- resumes a process to stop it with "interrupted"

-- kernel.event.interruptible > 0 lets Ctrl+C stop what runs (the shell
-- counts it up around a program). Each terminal has its own count: the
-- screen's, and one per window of a window manager (see kernel.tty).
local fgInterruptible = 0
kernel.event = setmetatable({}, {
  __index = function(_, key)
    if key ~= "interruptible" then return nil end
    local t = currentProc and currentProc.tty
    if t then return t.interruptible or 0 end
    return fgInterruptible
  end,
  __newindex = function(ev, key, v)
    if key ~= "interruptible" then return rawset(ev, key, v) end
    local t = currentProc and currentProc.tty
    if t then t.interruptible = v else fgInterruptible = v end
  end,
})

function kernel.event.listen(name, fn)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], fn)
end

-- Wait for a signal (or `timeout` seconds) and return it. In the
-- foreground this is where background processes run; inside a background
-- process it hands control back to the scheduler instead.
function kernel.event.pull(timeout, filter)
  local deadline = computer.uptime() + (timeout or math.huge)
  if currentProc and coroutine.running() == currentProc.co then
    local sig = table.pack(coroutine.yield(deadline, filter))
    if sig[1] == INTERRUPT then error("interrupted", 0) end
    return table.unpack(sig, 1, sig.n)
  end
  while true do
    local now = computer.uptime()
    local remaining = deadline - now
    if remaining <= 0 then runProcesses(); return nil end
    local wait = math.min(remaining, 1)
    for _, p in pairs(procs) do wait = math.min(wait, math.max(0, p.wake - now)) end
    local sig = table.pack(computer.pullSignal(wait))
    if not sig[1] then
      runProcesses()
    else
      if listeners[sig[1]] then
        for _, fn in ipairs(listeners[sig[1]]) do
          pcall(fn, table.unpack(sig, 1, sig.n))
        end
      end
      -- Ctrl+C stops the running program while one is (the shell sets
      -- interruptible), not the line being typed at the prompt
      if sig[1] == "key_down" or sig[1] == "key_up" then
        if sig[4] == 29 or sig[4] == 157 then
          ctrlHeld = sig[1] == "key_down"
        elseif sig[1] == "key_down" and sig[4] == 46 and ctrlHeld
            and fgInterruptible > 0 then
          error("interrupted", 0)
        end
      end
      runProcesses(sig)
      if not filter or sig[1] == filter then
        return table.unpack(sig, 1, sig.n)
      end
    end
  end
end

-- ============================================================
-- Users and permissions
-- ============================================================
-- Who is running. The kernel keeps this itself; the shell's $USER only
-- mirrors it, so `export USER=root` changes nothing.
local currentUser = "root"
local privileged  = 0       -- > 0 while the kernel acts on a user's behalf
local DENIED      = "permission denied"

function kernel.user() return currentUser end

-- Absolute path without "." / ".." / "//" parts, for permission checks.
local function clean(path)
  local parts = {}
  for seg in path:gsub("\\", "/"):gmatch("[^/]+") do
    if seg == ".." then parts[#parts] = nil elseif seg ~= "." then parts[#parts + 1] = seg end
  end
  return "/" .. table.concat(parts, "/")
end

-- Every file has an owner, a group and a mode (rwx for owner, group and
-- others, as on Linux). The disks cannot store them, so only the files
-- chmod or chown were used on are listed in PERMS ("755 owner group
-- path" lines); all others get theirs from where they are:
--   /home/<user>/...   owned by <user>, rw-r--r--
--   /tmp, /mnt         anyone may read and write
--   /etc/shadow        root only
--   everything else    owned by root, rw-r--r--
-- Root may do anything. A directory listed in PERMS also needs x for
-- the files inside it. Read (r) and write (w) are checked; x on a file
-- is shown but not enforced. This guards against mistakes and other
-- users; it is no sandbox: a program can still reach the disk through
-- `component` directly.
local PERMS = "/var/lib/perms"
local perms                  -- path -> { mode, owner, group }; loaded when first needed
local groupsOf = {}          -- user -> { group = true }, from /etc/group and /etc/passwd

local function readPrivileged(path)
  privileged = privileged + 1
  local ok, data = pcall(function() return kernel.fs.exists(path) and kernel.fs.readAll(path) end)
  privileged = privileged - 1
  return ok and data or nil
end

local function loadPerms()
  if perms then return perms end
  perms = {}
  for line in (readPrivileged(PERMS) or ""):gmatch("[^\r\n]+") do
    local mode, owner, group, path = line:match("^(%d+) (%S+) (%S+) (.+)$")
    if mode then perms[path] = { mode = tonumber(mode, 8), owner = owner, group = group } end
  end
  return perms
end

local function savePerms()
  local paths, lines = {}, {}
  for p in pairs(perms) do paths[#paths + 1] = p end
  table.sort(paths)
  for _, p in ipairs(paths) do
    local m = perms[p]
    lines[#lines + 1] = ("%o %s %s %s"):format(m.mode, m.owner, m.group, p)
  end
  privileged = privileged + 1
  local ok, err = pcall(kernel.fs.writeAll, PERMS, #lines > 0 and table.concat(lines, "\n") .. "\n" or "")
  privileged = privileged - 1
  if not ok then error(err, 0) end
end

local function under(p, dir) return p == dir or p:sub(1, #dir + 1) == dir .. "/" end

-- The owner, group and mode of a path that is not listed in PERMS.
local function defaultMeta(p, isDir)
  local user = p:match("^/home/([^/]+)")
  if user then return { owner = user, group = "users", mode = isDir and 493 or 420 } end      -- 755 / 644
  if under(p, "/tmp") or under(p, "/mnt") then
    return { owner = "root", group = "root", mode = isDir and 511 or 438 }                   -- 777 / 666
  end
  if p == "/etc/shadow" then return { owner = "root", group = "root", mode = 384 } end      -- 600
  return { owner = "root", group = "root", mode = isDir and 493 or 420 }
end

local function metaOf(p, isDir) return loadPerms()[p] or defaultMeta(p, isDir) end

-- The groups a user is in: listed as a member in /etc/group, or the
-- primary group from /etc/passwd. Forgotten whenever either file changes.
local function inGroup(user, group)
  local set = groupsOf[user]
  if not set then
    set = {}
    local byGid = {}
    for line in (readPrivileged("/etc/group") or ""):gmatch("[^\r\n]+") do
      local name, gid, members = line:match("^([^:]*):[^:]*:([^:]*):(.*)$")
      if name then
        byGid[gid] = name
        for m in members:gmatch("[^,%s]+") do if m == user then set[name] = true end end
      end
    end
    for line in (readPrivileged("/etc/passwd") or ""):gmatch("[^\r\n]+") do
      local name, gid = line:match("^([^:]*):[^:]*:[^:]*:([^:]*):")
      if name == user and byGid[gid] then set[byGid[gid]] = true end
    end
    groupsOf[user] = set
  end
  return set[group] == true
end

-- May the current user do `bit` (4 read, 2 write, 1 execute) to m?
local function permits(m, bit)
  local shift = 0
  if m.owner == currentUser then shift = 6 elseif inGroup(currentUser, m.group) then shift = 3 end
  return (m.mode >> shift) & bit ~= 0
end

local function allowed(path, write)
  if currentUser == "root" or privileged > 0 then return true end
  local p = clean(path)
  -- directories listed in PERMS on the way must let us through (x)
  local list = loadPerms()
  local dir = p:match("^(.*)/[^/]*$")
  while dir and dir ~= "" do
    if list[dir] and not permits(list[dir], 1) then return false end
    dir = dir:match("^(.*)/[^/]*$")
  end
  if not write then return permits(metaOf(p), 4) end
  -- an existing file needs w itself, a new one w on its directory
  if not list[p] and not kernel.fs.exists(p) then p = p:match("^(.*)/[^/]*$") or "/" end
  if p == "" then p = "/" end
  return permits(metaOf(p), 2)
end

-- ============================================================
-- Virtual File System
-- ============================================================
local mounts = {}      -- path -> proxy
kernel.fs = {}

-- Counts every change that can add, remove or replace a file (writing,
-- removing, renaming, mounting). What the shell remembers about files
-- (where a command is, a small program's text) is good while it stays.
local generation = 0
local function bump() generation = generation + 1 end
function kernel.fs.generation() return generation end

function kernel.fs.mount(path, proxy)
  if currentUser ~= "root" then return nil, DENIED end
  mounts[path] = proxy
  bump()
  return true
end

function kernel.fs.umount(path)
  if currentUser ~= "root" then return nil, DENIED end
  mounts[path] = nil
  bump()
  return true
end

function kernel.fs.mounts()
  local list = {}
  for p, proxy in pairs(mounts) do list[#list+1] = { path = p, proxy = proxy } end
  table.sort(list, function(a, b) return #a.path > #b.path end)
  return list
end

local function resolve(path)
  -- Normalize path
  path = path:gsub("\\", "/"):gsub("/+", "/")
  if path:sub(1,1) ~= "/" then path = "/" .. path end
  -- the longest mount point the path lies under (this runs for every file
  -- access, so no list is built or sorted)
  local best
  for mp in pairs(mounts) do
    if (mp == "/" or path == mp or path:sub(1, #mp + 1) == mp .. "/") and (not best or #mp > #best) then
      best = mp
    end
  end
  if not best then return nil, "no mount for " .. path end
  local sub = path:sub(#best + 1)
  if sub == "" then sub = "/" end
  if sub:sub(1,1) ~= "/" then sub = "/" .. sub end
  return mounts[best], sub
end
kernel.fs.resolve = resolve

-- True for a directory something is mounted below (/mnt), even when it
-- does not exist on the disk itself.
local function holdsMount(path)
  local dir = clean(path)
  for mp in pairs(mounts) do
    if mp ~= "/" and mp:sub(1, #dir + 1) == (dir == "/" and "/" or dir .. "/") then return true end
  end
  return false
end

function kernel.fs.exists(path)
  local p, sub = resolve(path); if not p then return false end
  return p.exists(sub) or holdsMount(path)
end

function kernel.fs.isDirectory(path)
  local p, sub = resolve(path); if not p then return false end
  return p.isDirectory(sub) or holdsMount(path)
end

function kernel.fs.size(path)
  local p, sub = resolve(path); if not p then return 0 end
  return p.size(sub)
end

function kernel.fs.list(path)
  local p, sub = resolve(path); if not p then return {} end
  local out, seen = {}, {}
  for _, n in ipairs(p.list(sub) or {}) do
    out[#out+1] = n
    seen[(n:gsub("/$", ""))] = true
  end
  -- mount points show up in their parent directory (/mnt/<id>/)
  local dir = clean(path)
  for mp in pairs(mounts) do
    local parent, name = mp:match("^(.*)/([^/]+)$")
    if name and (parent == "" and "/" or parent) == dir and not seen[name] then
      out[#out+1] = name .. "/"
    end
  end
  table.sort(out)
  return out
end

function kernel.fs.makeDirectory(path)
  if not allowed(path, true) then return false, DENIED end
  local p, sub = resolve(path); if not p then return false end
  bump()
  return p.makeDirectory(sub)
end

-- Entries in PERMS for path and everything below it move to `to` (or go
-- away with to = nil) when the files themselves do.
local function movePerms(path, to)
  local list, changed = loadPerms(), false
  for p, m in pairs(list) do
    if under(p, path) then
      list[p] = nil
      if to then list[to .. p:sub(#path + 1)] = m end
      changed = true
    end
  end
  if changed then savePerms() end
end

function kernel.fs.remove(path)
  if not allowed(path, true) then return false, DENIED end
  local p, sub = resolve(path); if not p then return false end
  bump()
  local ok, err = p.remove(sub)
  if ok then movePerms(clean(path), nil) end
  return ok, err
end

function kernel.fs.rename(from, to)
  if not allowed(from, true) or not allowed(to, true) then return false, DENIED end
  local pa, sa = resolve(from)
  local pb, sb = resolve(to)
  if not pa or not pb or pa.address ~= pb.address then return false, "cross-device" end
  bump()
  local ok, err = pa.rename(sa, sb)
  if ok then movePerms(clean(from), clean(to)) end
  return ok, err
end

-- { owner, group, mode, listed }: listed when chmod/chown set them.
function kernel.fs.stat(path)
  local p = clean(path)
  local m = metaOf(p, kernel.fs.isDirectory(p))
  return { owner = m.owner, group = m.group, mode = m.mode, listed = loadPerms()[p] ~= nil }
end

-- chmod: root or the owner may change a file's mode (a number, 0-4095).
function kernel.fs.chmod(path, mode)
  local p = clean(path)
  if not kernel.fs.exists(p) then return nil, "no such file" end
  local m = metaOf(p, kernel.fs.isDirectory(p))
  if currentUser ~= "root" and m.owner ~= currentUser then return nil, DENIED end
  loadPerms()[p] = { owner = m.owner, group = m.group, mode = mode & 4095 }
  savePerms()
  return true
end

-- chown: only root may give a file to another owner and/or group.
function kernel.fs.chown(path, owner, group)
  local p = clean(path)
  if currentUser ~= "root" then return nil, DENIED end
  if not kernel.fs.exists(p) then return nil, "no such file" end
  local m = metaOf(p, kernel.fs.isDirectory(p))
  loadPerms()[p] = { owner = owner or m.owner, group = group or m.group, mode = m.mode }
  savePerms()
  return true
end

function kernel.fs.open(path, mode)
  local writing = (mode or "r"):find("[wa]") ~= nil
  if not allowed(path, writing) then return nil, DENIED end
  if writing then
    local c = clean(path)
    -- someone edits the account files or PERMS by hand: read them again
    if c == "/etc/group" or c == "/etc/passwd" then groupsOf = {} end
    if c == PERMS and privileged == 0 then perms = nil end
    bump()
  end
  local p, sub = resolve(path); if not p then return nil, "not found" end
  local h, err = p.open(sub, mode or "r")
  if not h then return nil, err end
  local file = {}
  function file:read(n) return p.read(h, n or math.huge) end
  function file:write(d) return p.write(h, d) end
  function file:seek(w, o) return p.seek(h, w or "set", o or 0) end
  function file:close() return p.close(h) end
  -- one line at a time, read from the disk in large pieces (each read is a
  -- component call, so never one character at a time)
  function file:lines()
    local buf, pos, eof = "", 1, false
    return function()
      while true do
        local e = buf:find("\n", pos, true)
        if e then
          local line = buf:sub(pos, e - 1)
          pos = e + 1
          return line
        end
        if eof then
          if pos > #buf then return nil end
          local line = buf:sub(pos)
          pos = #buf + 1
          return line
        end
        local chunk = p.read(h, math.huge)
        if chunk then buf = buf:sub(pos) .. chunk; pos = 1 else eof = true end
      end
    end
  end
  return file
end

function kernel.fs.readAll(path)
  local f, err = kernel.fs.open(path, "r"); if not f then return nil, err end
  local parts = {}
  while true do
    local c = f:read(math.huge); if not c then break end
    parts[#parts + 1] = c
  end
  f:close()
  return table.concat(parts)
end

function kernel.fs.writeAll(path, data)
  local f, err = kernel.fs.open(path, "w"); if not f then return nil, err end
  f:write(data); f:close(); return true
end

-- Mount the boot filesystem at /
kernel.fs.mount("/", _G.bootfs)
-- Auto-mount additional filesystems at /mnt/<addr8>, also the ones
-- inserted later (a floppy); a removed disk is unmounted.
local function automount(addr)
  if addr ~= _G.bootfs.address then mounts["/mnt/" .. addr:sub(1, 8)] = component.proxy(addr); bump() end
end
for addr in component.list("filesystem") do automount(addr) end
kernel.event.listen("component_added", function(_, addr, kind)
  if kind == "filesystem" then automount(addr) end
end)
kernel.event.listen("component_removed", function(_, addr, kind)
  if kind ~= "filesystem" then return end
  for path, proxy in pairs(mounts) do
    if proxy.address == addr and path ~= "/" then mounts[path] = nil; bump() end
  end
end)

-- ============================================================
-- require() / package loader
-- ============================================================
package = { loaded = {}, path = "/lib/?.lua;/usr/lib/?.lua;/lib/?/init.lua" }
_G.package = package

function _G.require(name)
  if package.loaded[name] then return package.loaded[name] end
  for pat in package.path:gmatch("[^;]+") do
    local p = pat:gsub("%?", (name:gsub("%.", "/")))
    if kernel.fs.exists(p) then
      local src = kernel.fs.readAll(p)
      local fn, err = load(src, "=" .. p, "t", _G)
      if not fn then error(err, 2) end
      local mod = fn() or true
      package.loaded[name] = mod
      return mod
    end
  end
  error("module '" .. name .. "' not found", 2)
end

-- ============================================================
-- Accounts (the files are handled by /lib/auth.lua)
-- ============================================================
-- Run fn with the permission checks off: lets the kernel read /etc/shadow
-- for sudo or change a password for passwd on a user's behalf.
local function asKernel(fn, ...)
  privileged = privileged + 1
  local res = table.pack(pcall(fn, ...))
  privileged = privileged - 1
  -- /lib/auth (with sha256 about 20 KiB) is needed only for these moments;
  -- let it go so it does not stay in memory for the whole session
  package.loaded.auth, package.loaded.sha256 = nil, nil
  if not res[1] then error(res[2], 0) end
  return table.unpack(res, 2, res.n)
end
local fio = { read = function(p) return kernel.fs.readAll(p) end,
              write = function(p, d) return kernel.fs.writeAll(p, d) end }
local function auth() return require("auth") end
local function lookup(name) return asKernel(function() return auth().user(fio, name) end) end

-- Run fn as `name`; $USER (and $HOME when given) follow along.
local function switch(name, home, fn, ...)
  local prevUser, prevEnv, prevHome = currentUser, _G.USER, _G.HOME
  -- inside a process the process itself changes user too: the scheduler
  -- puts its user back whenever it continues after waiting (sudo pacman
  -- in a window downloads, and must still be root afterwards)
  local p = currentProc
  local procUser, procHome = p and p.user, p and p.home
  currentUser, _G.USER = name, name
  if home then _G.HOME = home end
  if p then p.user = name; if home then p.home = home end end
  local res = table.pack(pcall(fn, ...))
  if p then p.user, p.home = procUser, procHome end
  currentUser, _G.USER, _G.HOME = prevUser, prevEnv, prevHome
  if not res[1] then error(res[2], 0) end
  return table.unpack(res, 2, res.n)
end

-- True if `password` is `name`'s. A plain-text password from before
-- ByteOS 1.4 is replaced by its hash on the way.
function kernel.checkPassword(name, password)
  return asKernel(function()
    local ok, legacy = auth().check(password, auth().storedHash(fio, name))
    if ok and legacy then auth().setPassword(fio, name, password) end
    return ok == true
  end)
end

local SUDO_TIMEOUT = 300   -- seconds a correct sudo password is remembered
local stamps = {}          -- user -> uptime of their last correct sudo password

-- Run fn as `name` without a password. Only root may (login does this).
function kernel.runAs(name, fn, ...)
  if currentUser ~= "root" then error(DENIED, 2) end
  local u = lookup(name)
  if not u then error("no such user: " .. tostring(name), 2) end
  local res = table.pack(pcall(switch, name, u.home, fn, ...))
  stamps[name] = nil  -- the next login asks for the sudo password again
  if not res[1] then error(res[2], 0) end
  return table.unpack(res, 2, res.n)
end

function kernel.sudoNeedsPassword()
  local t = stamps[currentUser]
  return currentUser ~= "root" and not (t and computer.uptime() - t <= SUDO_TIMEOUT)
end

function kernel.sudoForget() stamps[currentUser] = nil end

-- sudo: run fn as root. Only members of wheel; they give their own
-- password, which is remembered for SUDO_TIMEOUT seconds.
-- Returns true, fn's results or nil, "notsudoer" | "password".
function kernel.sudo(password, fn, ...)
  local name = currentUser
  if name ~= "root" then
    if not asKernel(function() return auth().inGroup(fio, name, "wheel") end) then
      return nil, "notsudoer"
    end
    if kernel.sudoNeedsPassword() and not kernel.checkPassword(name, password) then
      return nil, "password"
    end
    stamps[name] = computer.uptime()
  end
  return true, switch("root", nil, fn, ...)
end

-- su: run fn as `name`. Root needs no password, everyone else `name`'s.
-- Returns true, fn's results or nil, "unknown" | "password".
function kernel.su(name, password, fn, ...)
  local u = lookup(name)
  if not u then return nil, "unknown" end
  if currentUser ~= "root" and not kernel.checkPassword(name, password) then
    return nil, "password"
  end
  return true, switch(name, u.home, fn, ...)
end

-- passwd: root sets anyone's password; a user only their own, giving the
-- current one first. Returns true or nil, reason.
function kernel.changePassword(name, old, new)
  if not lookup(name) then return nil, "user '" .. tostring(name) .. "' does not exist" end
  if currentUser ~= "root" then
    if name ~= currentUser then return nil, DENIED end
    if not kernel.checkPassword(name, old) then return nil, "Authentication failure" end
  end
  asKernel(function() auth().setPassword(fio, name, new) end)
  return true
end

-- ============================================================
-- Logging
-- ============================================================
-- kernel.log(message, tag) keeps the line in memory for dmesg (everything
-- since boot) and appends it to /var/log/messages as
-- "Oct 03 12:00:01 byteos tag: message". Any user may log.
local ring = _G.BOOTLOG or {}   -- what init.lua printed before the kernel ran
local LOGFILE, LOGMAX = "/var/log/messages", 32768

local function writeLog(entries)
  pcall(asKernel, function()
    if not kernel.fs.isDirectory("/var/log") then kernel.fs.makeDirectory("/var/log") end
    local f = kernel.fs.open(LOGFILE, "a")
    if not f then return end
    for _, e in ipairs(entries) do
      f:write(("%s %s %s: %s\n"):format(e.date, _G.HOSTNAME or "byteos", e.tag, e.msg))
    end
    f:close()
    if kernel.fs.size(LOGFILE) > LOGMAX then -- keep the newer half
      local text = kernel.fs.readAll(LOGFILE) or ""
      local cut = text:find("\n", #text - LOGMAX // 2, true) or 0
      kernel.fs.writeAll(LOGFILE, text:sub(cut + 1))
    end
  end)
end

function kernel.log(msg, tag)
  -- the real time once timesyncd has set it (lib/clock), else the world's
  local clock = package.loaded.clock
  local date = clock and clock.synced() and clock.date("%b %d %H:%M:%S") or os.date("%b %d %H:%M:%S")
  local e = { t = computer.uptime(), tag = tostring(tag or "kernel"), msg = tostring(msg), date = date }
  ring[#ring + 1] = e
  if #ring > 300 then table.remove(ring, 1) end
  writeLog({ e })
end

-- The messages since boot: { t = uptime, tag, msg }, oldest first.
function kernel.dmesg()
  local out = {}
  for i, e in ipairs(ring) do out[i] = { t = e.t, tag = e.tag, msg = e.msg } end
  return out
end

-- the boot lines init.lua collected before the kernel existed
for _, e in ipairs(ring) do e.date = e.date or os.date("%b %d %H:%M:%S") end
writeLog(ring)
_G.klog = function(msg) kernel.log(msg, "kernel") end

-- ============================================================
-- Processes
-- ============================================================
-- A background process is a coroutine. Processes run whenever the
-- foreground waits in kernel.event.pull (at the prompt, in sleep, ...):
-- each one is resumed with the signal it waits for, or with nothing when
-- its timeout passes. A process waits with kernel.event.pull as well,
-- which yields back here. Keyboard input stays with the foreground, and
-- every process runs with the permissions of the user who started it.
local FOREGROUND_ONLY = { key_down = true, key_up = true, clipboard = true }
local nextPid = 2      -- 1 is init
local finished = {}    -- pid -> process that ended (the last 50)
local finishedOrder = {}

local function ended(p, state, result)
  procs[p.pid] = nil
  p.state, p.result, p.ended = state, result, computer.uptime()
  finished[p.pid] = p
  finishedOrder[#finishedOrder + 1] = p.pid
  if #finishedOrder > 50 then finished[table.remove(finishedOrder, 1)] = nil end
  if state == "failed" then
    kernel.log(("process %d (%s) failed: %s"):format(p.pid, p.name, tostring(result)), "kernel")
  end
  if p.onexit then pcall(p.onexit, p) end
end

-- Each process has its own user, $HOME and working directory: a `cd` in
-- the background does not move the shell in the foreground.
local function resume(p, ...)
  p.fresh = nil
  local prevUser, prevEnv, prevHome, prevPwd = currentUser, _G.USER, _G.HOME, _G.PWD
  currentUser, _G.USER, _G.HOME, _G.PWD = p.user, p.user, p.home, p.pwd
  currentProc = p
  local res = table.pack(coroutine.resume(p.co, ...))
  currentProc = nil
  p.home, p.pwd = _G.HOME, _G.PWD
  currentUser, _G.USER, _G.HOME, _G.PWD = prevUser, prevEnv, prevHome, prevPwd
  if coroutine.status(p.co) == "dead" then
    if res[1] then ended(p, "done", res[2]) else ended(p, "failed", tostring(res[2])) end
  else
    p.wake, p.filter = res[2] or math.huge, res[3]
  end
end

runProcesses = function(sig)
  local now = computer.uptime()
  local list = {}
  for _, p in pairs(procs) do list[#list + 1] = p end
  table.sort(list, function(a, b) return a.pid < b.pid end)
  for _, p in ipairs(list) do
    if procs[p.pid] then
      if sig and sig[1] and not FOREGROUND_ONLY[sig[1]] and (not p.filter or p.filter == sig[1]) then
        resume(p, table.unpack(sig, 1, sig.n))
      elseif now >= p.wake then
        resume(p)
      end
    end
  end
end

kernel.process = {}

-- Start fn(...) as a background process. opts: name, user (only root may
-- start one as someone else), onexit = function(process). Returns the pid.
function kernel.process.spawn(fn, opts, ...)
  opts = opts or {}
  local user, home, pwd = currentUser, _G.HOME, _G.PWD
  if opts.user and opts.user ~= currentUser then
    if currentUser ~= "root" then return nil, DENIED end
    local u = lookup(opts.user)
    if not u then return nil, "no such user: " .. tostring(opts.user) end
    user, home, pwd = opts.user, u.home, u.home
  end
  -- a process stays on its parent's terminal, in the background there;
  -- opts.tty puts it in the foreground of a terminal (a window)
  local tty, fg = currentProc and currentProc.tty, false
  if opts.tty then
    tty, fg = opts.tty, opts.foreground ~= false
    tty.owner = tty.owner or currentUser -- whoever opened the window
  end
  local args = table.pack(...)
  local p = {
    pid = nextPid, name = opts.name or "?", user = user, home = home, pwd = pwd or "/", started = computer.uptime(),
    wake = 0, onexit = opts.onexit, tty = tty, fg = fg, fresh = true,
    co = coroutine.create(function() return fn(table.unpack(args, 1, args.n)) end),
  }
  nextPid = nextPid + 1
  procs[p.pid] = p
  return p.pid
end

-- The pid of the process that is running, nil in the foreground.
function kernel.process.current() return currentProc and currentProc.pid end

-- The terminal of the running process (nil: the screen itself), and
-- whether it is in the foreground there (gets the keys and Ctrl+C).
function kernel.process.tty() return currentProc and currentProc.tty end
function kernel.process.isForeground() return currentProc == nil or currentProc.fg == true end

-- ---- Terminals ----------------------------------------------------------------
-- A window manager gives each window a terminal (any table) and starts its
-- shell with spawn(fn, { tty = t }). Keys only reach the foreground of the
-- screen, the window manager, which hands them on to the window in focus.
kernel.tty = {}

local function onTty(t, fgOnly)
  local list = {}
  for _, p in pairs(procs) do
    if p.tty == t and (p.fg or not fgOnly) then list[#list + 1] = p end
  end
  table.sort(list, function(a, b) return a.pid < b.pid end)
  return list
end

-- A terminal belongs to whoever opened it: they type into it and close
-- it, also while a program there runs as someone else (sudo).
local function ownsTty(t, list)
  if currentUser == "root" then return true end
  if t.owner then return t.owner == currentUser end
  for _, p in ipairs(list) do if p.user ~= currentUser then return false end end
  return true
end

-- Give a signal (key_down, key_up, clipboard, ...) to the foreground of
-- terminal t. Ctrl+C stops the program running there, as on the screen.
function kernel.tty.input(t, ...)
  local sig = table.pack(...)
  local name, code = sig[1], sig[4]
  local list = onTty(t, true)
  if not ownsTty(t, list) then return nil, DENIED end
  if name == "key_down" or name == "key_up" then
    if code == 29 or code == 157 then
      t.ctrlHeld = name == "key_down"
    elseif name == "key_down" and code == 46 and t.ctrlHeld and (t.interruptible or 0) > 0 then
      for _, p in ipairs(list) do if procs[p.pid] then resume(p, INTERRUPT) end end
      return true
    end
  end
  for _, p in ipairs(list) do
    if procs[p.pid] and p.fresh then resume(p) end -- not started yet: up to its first wait
    if procs[p.pid] and (not p.filter or p.filter == name) then resume(p, ...) end
  end
  return true
end

-- Stop every process on terminal t (its window was closed), whoever
-- they run as, like a hangup.
local stop
function kernel.tty.hangup(t)
  local list = onTty(t)
  if not ownsTty(t, list) then return nil, DENIED end
  for _, p in ipairs(list) do if procs[p.pid] then stop(p) end end
  return true
end

local function describe(p, state)
  return { pid = p.pid, name = p.name, user = p.user, started = p.started, ended = p.ended,
           state = state or p.state, result = p.result }
end

-- All processes, init (pid 1) first; state "running" or "sleeping".
function kernel.process.list()
  local out = { { pid = 1, name = "init", user = "root", started = 0, state = "running" } }
  local now = computer.uptime()
  for _, p in pairs(procs) do
    out[#out + 1] = describe(p, (p == currentProc or p.wake <= now) and "running" or "sleeping")
  end
  table.sort(out, function(a, b) return a.pid < b.pid end)
  return out
end

-- A running or recently ended process ("done", "failed", "killed"), or nil.
function kernel.process.info(pid)
  local p = procs[pid]
  if p then return describe(p, "running") end
  if finished[pid] then return describe(finished[pid]) end
end

-- Stop a process; only root or the user who started it may.
function kernel.process.kill(pid)
  if pid == 1 then return nil, "init cannot be killed" end
  local p = procs[pid]
  if not p then return nil, "no such process" end
  if currentUser ~= "root" and currentUser ~= p.user then return nil, DENIED end
  stop(p)
  return true
end

function stop(p)
  if p == currentProc then
    p.wake = 0
    p.co = coroutine.create(function() end) -- ends at its next turn
  end
  ended(p, "killed")
end

-- ============================================================
-- Misc
-- ============================================================
function kernel.uptime() return computer.uptime() end
function kernel.shutdown(reboot) computer.shutdown(reboot) end

_G.kprint("kernel ready: " .. tostring(#kernel.fs.mounts()) .. " mount(s)")
