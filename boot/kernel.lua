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
kernel.event = { interruptible = 0 }

function kernel.event.listen(name, fn)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], fn)
end

function kernel.event.pull(timeout, filter)
  local deadline = computer.uptime() + (timeout or math.huge)
  while true do
    local remaining = deadline - computer.uptime()
    if remaining <= 0 then return nil end
    local sig = { computer.pullSignal(math.min(remaining, 1)) }
    if sig[1] then
      if listeners[sig[1]] then
        for _, fn in ipairs(listeners[sig[1]]) do
          pcall(fn, table.unpack(sig))
        end
      end
      -- Ctrl+C stops the running program while one is (the shell sets
      -- interruptible), not the line being typed at the prompt
      if sig[1] == "key_down" or sig[1] == "key_up" then
        if sig[4] == 29 or sig[4] == 157 then
          ctrlHeld = sig[1] == "key_down"
        elseif sig[1] == "key_down" and sig[4] == 46 and ctrlHeld
            and (kernel.event.interruptible or 0) > 0 then
          error("interrupted", 0)
        end
      end
      if not filter or sig[1] == filter then
        return table.unpack(sig)
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

-- Root may do anything. Other users may write only below their home, /tmp
-- and /mnt (removable disks), and may not read /etc/shadow. This guards
-- against mistakes and other users; it is no sandbox: a program can still
-- reach the disk through `component` directly.
local function allowed(path, write)
  if currentUser == "root" or privileged > 0 then return true end
  local p = clean(path)
  if p == "/etc/shadow" then return false end
  if not write then return true end
  local function under(dir) return p == dir or p:sub(1, #dir + 1) == dir .. "/" end
  return under("/home/" .. currentUser) or under("/tmp") or under("/mnt")
end

-- ============================================================
-- Virtual File System
-- ============================================================
local mounts = {}      -- path -> proxy
kernel.fs = {}

function kernel.fs.mount(path, proxy)
  if currentUser ~= "root" then return nil, DENIED end
  mounts[path] = proxy
  return true
end

function kernel.fs.umount(path)
  if currentUser ~= "root" then return nil, DENIED end
  mounts[path] = nil
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
  local best
  for _, m in ipairs(kernel.fs.mounts()) do
    if path == m.path or path:sub(1, #m.path + 1) == m.path .. "/" or m.path == "/" then
      if not best or #m.path > #best.path then best = m end
    end
  end
  if not best then return nil, "no mount for " .. path end
  local sub = path:sub(#best.path + 1)
  if sub == "" then sub = "/" end
  if sub:sub(1,1) ~= "/" then sub = "/" .. sub end
  return best.proxy, sub
end
kernel.fs.resolve = resolve

function kernel.fs.exists(path)
  local p, sub = resolve(path); if not p then return false end
  return p.exists(sub)
end

function kernel.fs.isDirectory(path)
  local p, sub = resolve(path); if not p then return false end
  return p.isDirectory(sub)
end

function kernel.fs.size(path)
  local p, sub = resolve(path); if not p then return 0 end
  return p.size(sub)
end

function kernel.fs.list(path)
  local p, sub = resolve(path); if not p then return {} end
  local out = {}
  for _, n in ipairs(p.list(sub) or {}) do out[#out+1] = n end
  table.sort(out)
  return out
end

function kernel.fs.makeDirectory(path)
  if not allowed(path, true) then return false, DENIED end
  local p, sub = resolve(path); if not p then return false end
  return p.makeDirectory(sub)
end

function kernel.fs.remove(path)
  if not allowed(path, true) then return false, DENIED end
  local p, sub = resolve(path); if not p then return false end
  return p.remove(sub)
end

function kernel.fs.rename(from, to)
  if not allowed(from, true) or not allowed(to, true) then return false, DENIED end
  local pa, sa = resolve(from)
  local pb, sb = resolve(to)
  if not pa or not pb or pa.address ~= pb.address then return false, "cross-device" end
  return pa.rename(sa, sb)
end

function kernel.fs.open(path, mode)
  if not allowed(path, (mode or "r"):find("[wa]") ~= nil) then return nil, DENIED end
  local p, sub = resolve(path); if not p then return nil, "not found" end
  local h, err = p.open(sub, mode or "r")
  if not h then return nil, err end
  local file = {}
  function file:read(n) return p.read(h, n or math.huge) end
  function file:write(d) return p.write(h, d) end
  function file:seek(w, o) return p.seek(h, w or "set", o or 0) end
  function file:close() return p.close(h) end
  function file:lines()
    return function()
      local buf = ""
      while true do
        local c = p.read(h, 1)
        if not c then if #buf > 0 then return buf end return nil end
        if c == "\n" then return buf end
        buf = buf .. c
      end
    end
  end
  return file
end

function kernel.fs.readAll(path)
  local f, err = kernel.fs.open(path, "r"); if not f then return nil, err end
  local data = ""
  while true do
    local c = f:read(math.huge); if not c then break end
    data = data .. c
  end
  f:close()
  return data
end

function kernel.fs.writeAll(path, data)
  local f, err = kernel.fs.open(path, "w"); if not f then return nil, err end
  f:write(data); f:close(); return true
end

-- Mount the boot filesystem at /
kernel.fs.mount("/", _G.bootfs)
-- Auto-mount additional filesystems at /mnt/<addr8>
for addr in component.list("filesystem") do
  if addr ~= _G.bootfs.address then
    kernel.fs.mount("/mnt/" .. addr:sub(1, 8), component.proxy(addr))
  end
end

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
  currentUser, _G.USER = name, name
  if home then _G.HOME = home end
  local res = table.pack(pcall(fn, ...))
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
-- Process model (very small cooperative)
-- ============================================================
kernel.process = { current = nil, list = {} }

function kernel.process.spawn(fn, name)
  local co = coroutine.create(fn)
  local pid = #kernel.process.list + 1
  kernel.process.list[pid] = { co = co, name = name or "proc", pid = pid }
  return pid
end

function kernel.process.run(pid, ...)
  local p = kernel.process.list[pid]; if not p then return end
  kernel.process.current = p
  local ok, err = coroutine.resume(p.co, ...)
  kernel.process.current = nil
  if not ok then
    _G.kprint("[panic] " .. p.name .. ": " .. tostring(err), 0xFF4444)
  end
  if coroutine.status(p.co) == "dead" then
    kernel.process.list[pid] = nil
  end
  return ok, err
end

-- ============================================================
-- Misc
-- ============================================================
function kernel.uptime() return computer.uptime() end
function kernel.shutdown(reboot) computer.shutdown(reboot) end

_G.kprint("kernel ready: " .. tostring(#kernel.fs.mounts()) .. " mount(s)")
