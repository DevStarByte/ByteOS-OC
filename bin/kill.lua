-- kill <pid|%job>... - stop background processes (yours, or any as root)
local args = arg or {}
if #args == 0 then term.write("usage: kill <pid|%job>...\n"); return 1 end
local rc = 0
for _, a in ipairs(args) do
  if a ~= "-9" and a ~= "-15" then -- signals are accepted but every kill is final
    local pid = tonumber(a)
    local job = a:match("^%%(%d+)$")
    if job then
      for _, j in ipairs(shell.jobs) do if j.id == tonumber(job) then pid = j.pid end end
    end
    if not pid then
      term.write("kill: " .. a .. ": no such job\n"); rc = 1
    else
      local ok, err = k.process.kill(pid)
      if not ok then term.write("kill: (" .. a .. ") - " .. tostring(err) .. "\n"); rc = 1 end
    end
  end
end
return rc
