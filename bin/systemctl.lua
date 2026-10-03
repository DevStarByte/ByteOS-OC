--[[
  systemctl [list-units]                 every service and its state
  systemctl status <name>                details and the last log lines
  systemctl start|stop|restart <name>    (root)
  systemctl enable|disable [--now] <name>  start at boot or not (root);
                                         --now also starts/stops it now
  Services are described in /etc/systemd/system/<name>.service.
]]--
local systemd = require("systemd")
local args = arg or {}
local T = term.theme
local cmd = args[1] or "list-units"
local now = false
local names = {}
for i = 2, #args do
  if args[i] == "--now" then now = true
  else names[#names + 1] = (args[i]:gsub("%.service$", "")) end
end

local function fail(msg) term.cwrite(T.err, "systemctl: "); term.write(msg .. "\n"); return 1 end
local function ago(t)
  local s = math.floor(computer.uptime() - t)
  if s < 60 then return s .. "s ago" end
  if s < 3600 then return ("%dmin %ds ago"):format(s // 60, s % 60) end
  return ("%dh %dmin ago"):format(s // 3600, (s % 3600) // 60)
end
local COLOR = { active = T.green, failed = T.red, activating = T.yellow }

if cmd == "list-units" or cmd == "list" then
  term.cwrite(T.bright, ("%-20s %-10s %-9s %s\n"):format("UNIT", "ACTIVE", "ENABLED", "DESCRIPTION"))
  for _, n in ipairs(systemd.list()) do
    local unit = systemd.load(n)
    local st = systemd.status(n)
    term.write(("%-20s "):format(n .. ".service"))
    term.cwrite(COLOR[st.active] or T.fg, ("%-10s "):format(st.active))
    term.write(("%-9s %s\n"):format(systemd.isEnabled(n) and "enabled" or "disabled",
      unit and unit.Description or "(broken unit)"))
  end
  return 0
end

if #names == 0 then return fail("no service named (see systemctl list-units)") end

if cmd == "status" then
  local rc = 0
  for _, n in ipairs(names) do
    local unit, err = systemd.load(n)
    if not unit then fail(err); rc = 4
    else
      local st = systemd.status(n)
      term.cwrite(COLOR[st.active] or T.fg, "● ")
      term.write(n .. ".service - " .. (unit.Description or n) .. "\n")
      term.write("     Loaded: loaded (" .. unit.path .. "; " .. (systemd.isEnabled(n) and "enabled" or "disabled") .. ")\n")
      term.write("     Active: ")
      local detail = st.active == "active" and "active (running)" or st.active
      term.cwrite(COLOR[st.active] or T.fg, detail)
      term.write((st.since and (" since " .. ago(st.since)) or "") .. "\n")
      if st.pid then term.write("   Main PID: " .. st.pid .. "\n") end
      if st.restarts > 0 then term.write("   Restarts: " .. st.restarts .. "\n") end
      local lines = {}
      for l in (fs.readAll("/var/log/messages") or ""):gmatch("[^\n]+") do
        if l:find(" " .. n .. ": ", 1, true) then lines[#lines + 1] = l end
      end
      if #lines > 0 then term.write("\n") end
      for j = math.max(1, #lines - 4), #lines do term.cwrite(T.muted, lines[j] .. "\n") end
      if st.active ~= "active" then rc = 3 end
    end
  end
  return rc
end

if k.user() ~= "root" then return fail("you need to be root to " .. cmd .. " services (try sudo)") end
local actions = {
  start = systemd.start, stop = systemd.stop, restart = systemd.restart,
  enable = function(n)
    local ok, err = systemd.enable(n)
    if ok and now then ok, err = systemd.start(n) end
    return ok, err
  end,
  disable = function(n)
    local ok, err = systemd.disable(n)
    if ok and now then ok, err = systemd.stop(n) end
    return ok, err
  end,
}
if not actions[cmd] then return fail("unknown command '" .. cmd .. "'") end
local rc = 0
for _, n in ipairs(names) do
  local ok, err = actions[cmd](n)
  if not ok then fail(tostring(err)); rc = 1 end
end
return rc
