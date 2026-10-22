--[[
  crontab - your scheduled jobs (crond runs them)

    crontab -l          show them
    crontab -e          change them in the editor ($EDITOR, else edit)
    crontab -r          remove them all
    crontab FILE        take them from FILE (- reads the input)
    -u USER             someone else's (root only)

  They are kept in ~/.crontab, one job per line:

    # min  hour  day  month  weekday  command
    */15   *     *    *      *        echo still here
    0      7     *    *      mon-fri  sh ~/bin/morning.sh
    @daily  rm -r /tmp/cache          @reboot  echo booted

  Fields take *, numbers, ranges (1-5), steps (*/15), lists (1,15) and
  names (jan, mon); weekday 0 and 7 are Sunday. @yearly @monthly @weekly
  @daily @hourly stand for the five fields; @reboot runs when crond starts.
  A job runs as you, in your home directory; what it prints goes to the
  system log (journalctl -u crond). /etc/crontab (root's) has a user name
  before the command. The crond service runs the jobs; it is off until
  needed, and crontab run by root offers to start it. Otherwise:

    sudo systemctl enable --now crond
]]--
local args = arg or {}
local cron = require("cron")
local user, action, source = k.user(), nil, nil
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-u" then i = i + 1; user = args[i]
  elseif a == "-l" or a == "-e" or a == "-r" then action = a
  elseif a == "-" or a:sub(1, 1) ~= "-" then action, source = "install", a
  else shell.err("crontab", "unknown option " .. a); return 2 end
  i = i + 1
end
if not action or not user then
  term.write("usage: crontab [-u USER] -l | -e | -r | FILE\n"); return 2
end
if user ~= k.user() and k.user() ~= "root" then
  shell.err("crontab", "only root may change another user's crontab"); return 1
end
local home = "/home/" .. user
if not fs.isDirectory(home) then shell.err("crontab", "no home directory for " .. user); return 1 end
local path = home .. "/.crontab"

-- Lines with mistakes, as "line N: why"; empty if all is well.
local function check(text)
  local bad, n = {}, 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local ok, why = cron.parse(line)
    if ok == false then bad[#bad + 1] = ("line %d: %s"):format(n, why) end
  end
  return bad
end

-- crond is off until someone has jobs: root is offered to turn it on
-- (at the keyboard), everyone else told how.
local function hint()
  local okS, systemd = pcall(require, "systemd")
  if not okS or systemd.status("crond").active == "active" then return end
  if k.user() == "root" and stdin.isTerminal then
    term.write("crond, which runs the jobs, is not running. Start it now and at every boot? [Y/n] ")
    local answer = term.read() or "n"
    if not answer:lower():match("^n") then
      systemd.enable("crond")
      local ok, err = systemd.start("crond")
      if not ok then shell.err("crontab", "cannot start crond: " .. tostring(err)); return end
      term.write("crond started\n")
    end
    return
  end
  term.write("note: crond is not running; start it with: sudo systemctl enable --now crond\n")
end

if action == "-l" then
  local text = fs.exists(path) and fs.readAll(path)
  if not text then shell.err("crontab", "no crontab for " .. user); return 1 end
  term.write(text)
  return 0
elseif action == "-r" then
  if not fs.exists(path) then shell.err("crontab", "no crontab for " .. user); return 1 end
  local ok, err = fs.remove(path)
  if not ok then shell.err("crontab", tostring(err)); return 1 end
  return 0
elseif action == "install" then
  local text, err
  if source == "-" then text = stdin.read("a") or ""
  else text, err = fs.readAll(shell.normalize(source)) end
  if not text then shell.err("crontab", source .. ": " .. tostring(err or "cannot read")); return 1 end
  local bad = check(text)
  if #bad > 0 then
    for _, b in ipairs(bad) do shell.err("crontab", b) end
    term.write("crontab: not installed\n"); return 1
  end
  local ok, werr = fs.writeAll(path, text)
  if not ok then shell.err("crontab", tostring(werr)); return 1 end
  hint()
  return 0
end

-- -e: edit until the jobs are fine (or the user gives up)
if not fs.exists(path) then
  local ok, err = fs.writeAll(path, "# min  hour  day  month  weekday  command\n")
  if not ok then shell.err("crontab", tostring(err)); return 1 end
end
local editor = (_G.EDITOR and _G.EDITOR ~= "") and _G.EDITOR or "edit"
while true do
  shell.run(editor .. " '" .. path:gsub("'", "'\\''") .. "'")
  local bad = check(fs.readAll(path) or "")
  if #bad == 0 then break end
  for _, b in ipairs(bad) do shell.err("crontab", b) end
  term.write("Edit again? [Y/n] ")
  local answer = term.read() or "n"
  if answer:lower():match("^n") then
    term.write("crontab: the bad lines are skipped until you fix them\n"); return 1
  end
end
hint()
return 0
