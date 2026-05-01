local pipe = require("pipe")
local event = require("event")
local process = require("process")
local computer = require("computer")

local thread = {}
local init_thread

local function waitForDeath(threads, timeout, all)
  checkArg(1, threads, "table")
  checkArg(2, timeout, "number", "nil")
  checkArg(3, all, "boolean")
  timeout = timeout or math.huge
  local mortician = {}
  local timed_out = true
  local deadline = computer.uptime() + timeout
  while deadline > computer.uptime() do
    local dieing = {}
    local living = false
    for _,t in ipairs(threads) do
      local mt = getmetatable(t)
      local result = mt.attached.data.result
      local proc_ok = type(result) ~= "table" or result[1]
      local ready_to_die = t:status() ~= "running" -- suspended is considered dead to exit
        or not proc_ok -- the thread is killed if its attached process has a non zero exit
      if ready_to_die then
        dieing[#dieing + 1] = t
        mortician[t] = true
      else
        living = true
      end
    end

    if all and not living or not all and #dieing > 0 then
      timed_out = false
      break
    end

    -- resume each non dead thread
    -- we KNOW all threads are event.pull blocked
    event.pull(deadline - computer.uptime())
  end

  for t in pairs(mortician) do
    t:kill()
  end

  if timed_out then
    return nil, "thread join timed out"
  end
  return true
end

function thread.waitForAny(threads, timeout)
  return waitForDeath(threads, timeout, false)
end

function thread.waitForAll(threads, timeout)
  return waitForDeath(threads, timeout, true)
end

local box_thread = {}

function box_thread:resume()
  local mt = getmetatable(self)
  if mt.__status ~= "suspended" then
    return nil, "cannot resume " .. mt.__status .. " thread"
  end
  mt.__status = "running"
  -- register the thread to wake up
  if coroutine.status(self.pco.root) == "suspended" and not mt.reg then
    mt.register(0)
  end
  return true
end

function box_thread:suspend()
  local mt = getmetatable(self)
  if mt.__status ~= "running" then
    return nil, "cannot suspend " .. mt.__status .. " thread"
  end
  mt.__status = "suspended"
  local pco_status = coroutine.status(self.pco.root)
  if pco_status == "running" or pco_status == "normal" then
    mt.coma()
  end
  return true
end

function box_thread:status()
  return getmetatable(self).__status
end

function box_thread:join(timeout)
  return waitForDeath({self}, timeout, true)
end

function box_thread:kill()
  getmetatable(self).close()
end

function box_thread:detach()
  return self:attach(init_thread)
end

function box_thread:attach(parent)
  local proc = process.info(parent)
  local mt = assert(getmetatable(self), "thread panic: no metadata")
  if not proc then return nil, "thread failed to attach, process not found" end
  if mt.attached == proc then return self end -- already attached

  -- remove from old parent
  local waiting_handler
  if mt.attached then
    -- registration happens on the attached proc, unregister before reparenting
    waiting_handler = mt.unregister()