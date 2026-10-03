--[[
  /usr/lib/notify.lua - desktop notifications

  Programs send notifications; a daemon (dunst) shows them.

    local notify = require("notify")
    notify.send(summary [, body] [, opts]) -> id | nil, "no notification daemon"
        opts: urgency = "low" | "normal" | "critical", timeout = seconds
              (0: until clicked), app = "the sender"
    notify.running()           -> true while a daemon listens
    notify.history             the last 50, oldest first

  A daemon calls notify.register(fn); fn(notification) gets
  { id, summary, body, urgency, timeout, app, time } for each one.
]]--
local notify = { history = {} }
local handlers, nextId = {}, 1

local function alive(h)
  if not h.pid then return true end
  local p = kernel.process.info(h.pid)
  return p and p.state == "running"
end

function notify.register(fn)
  handlers[#handlers + 1] = { fn = fn, pid = kernel.process.current() }
end
function notify.unregister(fn)
  for i = #handlers, 1, -1 do if handlers[i].fn == fn then table.remove(handlers, i) end end
end
function notify.running()
  for i = #handlers, 1, -1 do if not alive(handlers[i]) then table.remove(handlers, i) end end
  return #handlers > 0
end

function notify.send(summary, body, opts)
  opts = opts or {}
  local n = {
    id = nextId, summary = tostring(summary or ""), body = body and tostring(body) or "",
    urgency = opts.urgency or "normal", timeout = tonumber(opts.timeout),
    app = opts.app or "", time = computer.uptime(), user = kernel.user(),
  }
  nextId = nextId + 1
  notify.history[#notify.history + 1] = n
  if #notify.history > 50 then table.remove(notify.history, 1) end
  if not notify.running() then return nil, "no notification daemon is running (install dunst)" end
  for _, h in ipairs(handlers) do pcall(h.fn, n) end
  return n.id
end

return notify
