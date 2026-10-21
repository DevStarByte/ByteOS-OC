--[[
  /lib/cron.lua - crontab lines and when they are due (used by crond and
  crontab)

  A user's jobs are in ~/.crontab, the system's in /etc/crontab (which has
  a user name before the command):

    # min  hour  day  month  weekday  command
    */15   *     *    *      *        echo still here
    0      7     *    *      mon-fri  /home/alice/bin/morning.sh
    @daily  rm -r /tmp/cache          @reboot  echo booted

  Fields take *, numbers, ranges (1-5), steps (*/15, 0-30/10), lists
  (1,15) and names (jan, mon). Weekday 0 and 7 are Sunday. When both day
  and weekday are given, either one matching is enough (as in cron).
  @yearly @monthly @weekly @daily @hourly stand for the five fields,
  @reboot runs once when crond starts.

    cron.parse(line, withUser) -> job | nil (blank or comment) | false, why
    cron.due(job, now)         -> true when job runs in the minute `now`
                                  ({ min, hour, day, month, wday })
    cron.now()                 -> that table for this minute, and a key
    cron.tabs()                -> every job of every crontab, with .user
    cron.run(job)              -> start it as a background process
]]--

local k = _G.kernel
local fs = k.fs

local cron = {}

local RANGES = { { 0, 59 }, { 0, 23 }, { 1, 31 }, { 1, 12 }, { 0, 7 } }
local NAMES = {
  [4] = { jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12 },
  [5] = { sun = 0, mon = 1, tue = 2, wed = 3, thu = 4, fri = 5, sat = 6 },
}
local MACROS = { ["@yearly"] = "0 0 1 1 *", ["@annually"] = "0 0 1 1 *", ["@monthly"] = "0 0 1 * *",
  ["@weekly"] = "0 0 * * 0", ["@daily"] = "0 0 * * *", ["@midnight"] = "0 0 * * *", ["@hourly"] = "0 * * * *" }
local FIELD_NAMES = { "minute", "hour", "day", "month", "weekday" }

-- One field as a set { [n] = true }, or nil for * (anything); errors on a mistake.
local function field(text, i)
  if text == "*" then return nil end
  local lo, hi = RANGES[i][1], RANGES[i][2]
  local function num(s)
    local n = tonumber(s) or (NAMES[i] and NAMES[i][s:lower()])
    if not n or n < lo or n > hi or n % 1 ~= 0 then error(FIELD_NAMES[i] .. " '" .. s .. "' is out of range", 0) end
    return n
  end
  local set = {}
  for part in (text .. ","):gmatch("([^,]*),") do
    local range, step = part:match("^([^/]+)/(%d+)$")
    range, step = range or part, tonumber(step) or 1
    if step < 1 then error("a step of 0 in '" .. text .. "'", 0) end
    local a, b
    if range == "*" then a, b = lo, hi
    elseif range:find("-", 1, true) then
      local x, y = range:match("^(%w+)-(%w+)$")
      if not x then error("bad " .. FIELD_NAMES[i] .. " '" .. part .. "'", 0) end
      a, b = num(x), num(y)
    else
      a = num(range); b = part:find("/", 1, true) and hi or a
    end
    if a > b then error("backwards range '" .. part .. "'", 0) end
    for n = a, b, step do set[n] = true end
  end
  if i == 5 and set[7] then set[0] = true end
  return set
end

function cron.parse(line, withUser)
  line = line:gsub("\r$", "")
  if line:match("^%s*$") or line:match("^%s*#") then return nil end
  local words, rest = {}, line:match("^%s*(.-)%s*$")
  local macro = rest:match("^(@%a+)")
  local count = macro and 1 or 5
  if withUser then count = count + 1 end
  for _ = 1, count do
    local w, more = rest:match("^(%S+)%s*(.*)$")
    if not w then return false, "too few fields" end
    words[#words + 1] = w
    rest = more
  end
  if rest == "" then return false, "no command" end
  local job = { cmd = rest, line = line, user = withUser and words[#words] or nil }
  if macro then
    if macro == "@reboot" then job.reboot = true; return job end
    if not MACROS[macro] then return false, "unknown " .. macro end
    words = {}
    for w in MACROS[macro]:gmatch("%S+") do words[#words + 1] = w end
  end
  for i = 1, 5 do
    local ok, set = pcall(field, words[i], i)
    if not ok then return false, set end
    job[i] = set
  end
  return job
end

function cron.due(job, now)
  if job.reboot then return false end
  local t = { now.min, now.hour, now.day, now.month, now.wday }
  for i = 1, 4 do
    if i ~= 3 and job[i] and not job[i][t[i]] then return false end
  end
  local day, wday = job[3], job[5]
  if day and wday then return day[now.day] == true or wday[now.wday] == true end
  if day then return day[now.day] == true end
  if wday then return wday[now.wday] == true end
  return true
end

-- This minute in local time (the real time once timesyncd has it, else
-- the world's) and a key that changes with every minute.
function cron.now()
  local clock = require("clock")
  local key = clock.date("%Y-%m-%d %H:%M")
  local m, h, d, mo, w = clock.date("%M %H %d %m %w"):match("(%d+) (%d+) (%d+) (%d+) (%d+)")
  return { min = tonumber(m), hour = tonumber(h), day = tonumber(d), month = tonumber(mo), wday = tonumber(w) }, key
end

-- Every job in /etc/crontab and /home/<user>/.crontab; bad lines are
-- logged (once, when `warned` remembers them) and skipped.
function cron.tabs(warned)
  warned = warned or {}
  local jobs = {}
  local function add(path, user)
    local text = fs.exists(path) and fs.readAll(path)
    if not text then return end
    local n = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      n = n + 1
      local job, err = cron.parse(line, user == nil)
      if job then
        job.user = job.user or user
        jobs[#jobs + 1] = job
      elseif job == false then
        local msg = ("%s:%d: %s"):format(path, n, err)
        if not warned[msg] then warned[msg] = true; k.log(msg, "crond") end
      end
    end
  end
  add("/etc/crontab")
  for _, d in ipairs(fs.list("/home") or {}) do
    local user = d:match("^(.-)/$")
    if user then add("/home/" .. user .. "/.crontab", user) end
  end
  return jobs
end

-- Start a job as its user; what it prints goes to the system log.
function cron.run(job)
  local shell = require("shell")
  k.log(("(%s) CMD (%s)"):format(job.user, job.cmd), "crond")
  local pid, err = k.process.spawn(function()
    local pending = ""
    local function log(text)
      pending = pending .. text
      for line in pending:gmatch("([^\n]*)\n") do
        if line ~= "" then k.log(line, "crond") end
      end
      pending = pending:match("[^\n]*$")
    end
    local sink = setmetatable({}, { __newindex = function(_, _, text) log(text) end })
    shell.setErrorSink(log)
    _G.PWD = _G.HOME or "/"
    return shell.withIO({ output = sink }, shell.execute, job.cmd)
  end, { name = "cron: " .. job.cmd, user = job.user })
  if not pid then k.log(("(%s) cannot run %s: %s"):format(job.user, job.cmd, tostring(err)), "crond") end
  return pid
end

return cron
