--[[
  /lib/thread.lua - tiny cooperative thread library for ByteOS

  Sits on top of kernel.process + Lua coroutines. A "thread" is just a
  coroutine that the scheduler resumes round-robin until it dies, is
  killed, or is suspended. Threads can yield by calling thread.sleep(t)
  or thread.yield(); event.pull-style waiting goes through kernel.event.

  API:
    t = thread.create(fn, ...)   -- start a new thread, returns handle
    t:status()                   -- "running" | "suspended" | "dead"
    t:suspend()                  -- pause scheduling
    t:resume()                   -- unpause
    t:kill()                     -- mark dead, drop from scheduler
    t:join(timeout)              -- block current thread until t dies
    thread.current()             -- handle of the calling thread (or nil)
    thread.yield()               -- give other threads a turn
    thread.sleep(seconds)        -- suspend the current thread for N s
    thread.run()                 -- run the scheduler until all threads die
    thread.waitForAny(list, t)
    thread.waitForAll(list, t)
]]--

local k        = _G.kernel
local computer = _G.computer

local thread = {}

local threads = {}        -- list of live thread handles
local current_thread      -- handle currently executing

local STATUS_RUNNING   = "running"
local STATUS_SUSPENDED = "suspended"
local STATUS_DEAD      = "dead"

local function newHandle(co, name)
  local h = {
    co       = co,
    name     = name or "thread",
    _status  = STATUS_RUNNING,  -- "running" | "suspended" | "dead"
    wake     = 0,               -- earliest uptime() at which to resume
    result   = nil,             -- {ok, ...} once dead
  }

  function h:status() return self._status end

  function h:suspend()
    if self._status == STATUS_RUNNING then self._status = STATUS_SUSPENDED end
    return true
  end

  function h:resume()
    if self._status == STATUS_SUSPENDED then
      self._status = STATUS_RUNNING
      self.wake    = 0
    end
    return true
  end

  function h:kill() self._status = STATUS_DEAD end

  function h:join(timeout)
    local deadline = computer.uptime() + (timeout or math.huge)
    while self._status ~= STATUS_DEAD do
      if computer.uptime() >= deadline then
        return nil, "thread join timed out"
      end
      thread.yield()
    end
    return true
  end

  return h
end

function thread.current() return current_thread end

function thread.yield()
  if coroutine.running() then coroutine.yield() end
end

function thread.sleep(seconds)
  seconds = tonumber(seconds) or 0
  local t = current_thread
  if not t then
    -- Called from outside any thread: just busy-wait via event.pull
    k.event.pull(seconds)
    return
  end
  t.wake = computer.uptime() + seconds
  thread.yield()
end

function thread.create(fn, ...)
  local args = table.pack(...)
  local h
  local co = coroutine.create(function()
    local ok, err = pcall(function() fn(table.unpack(args, 1, args.n)) end)
    h.result = { ok, err }
    h._status = STATUS_DEAD
  end)
  h = newHandle(co, "thread")
  table.insert(threads, h)
  return h
end

local function alive()
  for _, t in ipairs(threads) do
    if t._status ~= STATUS_DEAD then return true end
  end
  return false
end

local function reap()
  for i = #threads, 1, -1 do
    if threads[i]._status == STATUS_DEAD then
      table.remove(threads, i)
    end
  end
end

function thread.run()
  while alive() do
    local now = computer.uptime()
    local ran_any = false
    for _, t in ipairs(threads) do
      if t._status == STATUS_RUNNING and now >= (t.wake or 0)
         and coroutine.status(t.co) ~= "dead" then
        current_thread = t
        local ok, err = coroutine.resume(t.co)
        current_thread = nil
        ran_any = true
        if not ok then
          t.result = { false, err }
          t._status = STATUS_DEAD
          if _G.kprint then _G.kprint("[thread] " .. tostring(err), 0xFF4444) end
        elseif coroutine.status(t.co) == "dead" then
          t._status = STATUS_DEAD
        end
      end
    end
    reap()
    if not ran_any then
      -- Everyone is suspended or sleeping -> let signals/timers tick
      local soonest = math.huge
      for _, t in ipairs(threads) do
        if t._status == STATUS_RUNNING and (t.wake or 0) < soonest then
          soonest = t.wake or 0
        end
      end
      local wait
      if soonest == math.huge then wait = 0.05
      else wait = math.max(0, soonest - computer.uptime()) end
      k.event.pull(wait)
    end
  end
end

local function waitFor(list, timeout, all)
  local deadline = computer.uptime() + (timeout or math.huge)
  while true do
    local dead, total = 0, #list
    for _, t in ipairs(list) do
      if t._status == STATUS_DEAD then dead = dead + 1 end
    end
    if all and dead == total then return true end
    if not all and dead > 0 then return true end
    if computer.uptime() >= deadline then
      return nil, "thread join timed out"
    end
    thread.yield()
  end
end

function thread.waitForAny(list, timeout) return waitFor(list, timeout, false) end
function thread.waitForAll(list, timeout) return waitFor(list, timeout, true)  end

return thread
