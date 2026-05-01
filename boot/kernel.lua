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
kernel.event = {}

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
      if not filter or sig[1] == filter then
        return table.unpack(sig)
      end
    end
  end
end

-- ============================================================
-- Virtual File System
-- ============================================================
local mounts = {}      -- path -> proxy
kernel.fs = {}

function kernel.fs.mount(path, proxy)
  mounts[path] = proxy
end

function kernel.fs.umount(path)
  mounts[path] = nil
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
  local p, sub = resolve(path); if not p then return false end
  return p.makeDirectory(sub)
end

function kernel.fs.remove(path)
  local p, sub = resolve(path); if not p then return false end
  return p.remove(sub)
end

function kernel.fs.rename(from, to)
  local pa, sa = resolve(from)
  local pb, sb = resolve(to)
  if not pa or not pb or pa.address ~= pb.address then return false, "cross-device" end
  return pa.rename(sa, sb)
end

function kernel.fs.open(path, mode)
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

_G.kprint("[    0.040] kernel ready :: " .. tostring(#kernel.fs.mounts()) .. " mount(s)")
