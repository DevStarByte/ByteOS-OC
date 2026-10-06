--[[
  /lib/systemd.lua - services, in the spirit of systemd

  A service is described by a unit file, /etc/systemd/system/<name>.service
  (yours) or /usr/lib/systemd/system/<name>.service (from a package):

    [Unit]
    Description=Says hello every minute

    [Service]
    ExecStart=/usr/bin/hellod --loud     a command line, run like in the shell
    User=root                            who it runs as (default root)
    Restart=no                           no | on-failure | always
    RestartSec=5                         seconds before a restart

  A running service is a background process (see kernel.process); what it
  prints goes to the system log under its name (journalctl -u <name>).
  Enabled services, listed in /etc/systemd/enabled, start at boot.
]]--

local k  = _G.kernel
local fs = k.fs

local systemd = {}

local DIRS    = { "/etc/systemd/system", "/usr/lib/systemd/system" }
local ENABLED = "/etc/systemd/enabled"
local MAX_RESTARTS = 5

local state = {}  -- name -> { pid, active, since, restarts, result, stopping }

local function unitPath(name)
  for _, d in ipairs(DIRS) do
    local p = d .. "/" .. name .. ".service"
    if fs.exists(p) then return p end
  end
end

-- The unit as { name, path, Description, ExecStart, User, Restart, RestartSec }.
function systemd.load(name)
  local path = unitPath(name)
  if not path then return nil, "Unit " .. name .. ".service not found." end
  local unit = { name = name, path = path, User = "root", Restart = "no", RestartSec = "5" }
  for line in (fs.readAll(path) or ""):gmatch("[^\r\n]+") do
    local key, value = line:match("^%s*([%w]+)%s*=%s*(.-)%s*$")
    if key then unit[key] = value end
  end
  if not unit.ExecStart or unit.ExecStart == "" then
    return nil, name .. ".service has no ExecStart="
  end
  return unit
end

-- Every unit name, sorted.
function systemd.list()
  local names, seen = {}, {}
  for _, d in ipairs(DIRS) do
    for _, f in ipairs(fs.list(d) or {}) do
      local n = f:match("^(.+)%.service$")
      if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
  end
  table.sort(names)
  return names
end

function systemd.isEnabled(name)
  for l in (fs.readAll(ENABLED) or ""):gmatch("[^\r\n]+") do
    if l == name then return true end
  end
  return false
end

local function setEnabled(name, on)
  local out = {}
  for l in (fs.readAll(ENABLED) or ""):gmatch("[^\r\n]+") do
    if l ~= name then out[#out + 1] = l end
  end
  if on then out[#out + 1] = name end
  if not fs.isDirectory("/etc/systemd") then fs.makeDirectory("/etc/systemd") end
  return fs.writeAll(ENABLED, table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

function systemd.enable(name)
  if not unitPath(name) then return nil, "Unit " .. name .. ".service not found." end
  return setEnabled(name, true)
end

function systemd.disable(name) return setEnabled(name, false) end

-- What a service prints: every complete line goes to the log.
local function logSink(name)
  local pending = ""
  return setmetatable({}, { __newindex = function(_, _, text)
    pending = pending .. text
    while true do
      local line, rest = pending:match("^([^\n]*)\n(.*)$")
      if not line then break end
      if line ~= "" then k.log(line, name) end
      pending = rest
    end
  end })
end

local start

local start -- below; a restart calls it before it is defined

local function exited(name, unit, p)
  local st = state[name]
  if not st or st.pid ~= p.pid then return end
  st.pid, st.result, st.since = nil, p.result, computer.uptime()
  if st.stopping or p.state == "killed" then
    st.active = "inactive"
    return
  end
  local failed = p.state == "failed" or (tonumber(p.result) or 0) ~= 0
  st.active = failed and "failed" or "inactive"
  k.log(("%s.service: %s (%s)"):format(name, failed and "Failed" or "Finished",
    p.state == "failed" and tostring(p.result) or ("status=" .. tostring(p.result or 0))), "systemd")
  local again = unit.Restart == "always" or (unit.Restart == "on-failure" and failed)
  if again and st.restarts < MAX_RESTARTS then
    st.restarts = st.restarts + 1
    st.active = "activating"
    k.process.spawn(function()
      k.event.pull(tonumber(unit.RestartSec) or 5)
      if st.active == "activating" then start(name, true) end
    end, { name = name .. " (restart timer)" })
  elseif again then
    k.log(name .. ".service: start request repeated too quickly, giving up", "systemd")
  end
end

-- Start a service; returns true or nil, reason.
start = function(name, isRestart)
  local unit, err = systemd.load(name)
  if not unit then return nil, err end
  local st = state[name] or { restarts = 0 }
  state[name] = st
  if st.pid and k.process.info(st.pid) and k.process.info(st.pid).state == "running" then return true end
  if not isRestart then st.restarts = 0 end
  local shell = require("shell")
  local pid, perr = k.process.spawn(function()
    local sink = logSink(name)
    shell.setErrorSink(function(text) sink[1] = text end) -- errors go to the log too
    return shell.run(unit.ExecStart, { output = sink })
  end, { name = name, user = unit.User, onexit = function(p) exited(name, unit, p) end })
  if not pid then return nil, perr end
  st.pid, st.active, st.since, st.stopping = pid, "active", computer.uptime(), false
  k.log("Started " .. (unit.Description or name) .. ".", "systemd")
  return true
end
systemd.start = function(name) return start(name, false) end

function systemd.stop(name)
  local st = state[name]
  if not st or not st.pid then
    if st then st.active = "inactive" end
    return true
  end
  st.stopping = true
  local ok, err = k.process.kill(st.pid)
  if not ok then return nil, err end
  st.active = "inactive"
  local unit = systemd.load(name)
  k.log("Stopped " .. ((unit and unit.Description) or name) .. ".", "systemd")
  return true
end

function systemd.restart(name)
  systemd.stop(name)
  return systemd.start(name)
end

-- { active = "active"|"inactive"|"failed"|"activating", pid, since, result }
function systemd.status(name)
  local st = state[name] or {}
  local active = st.active or "inactive"
  if active == "active" and not (st.pid and k.process.info(st.pid)
      and k.process.info(st.pid).state == "running") then
    active = "inactive"
  end
  return { active = active, pid = st.pid, since = st.since, result = st.result, restarts = st.restarts or 0 }
end

-- Start every enabled service (init does this at boot). Returns
-- { { name, description, ok, err }, ... }.
function systemd.boot()
  local out = {}
  for l in (fs.readAll(ENABLED) or ""):gmatch("[^\r\n]+") do
    local unit = systemd.load(l)
    local ok, err = systemd.start(l)
    out[#out + 1] = { name = l, description = unit and unit.Description or l, ok = ok, err = err }
  end
  return out
end

return systemd
