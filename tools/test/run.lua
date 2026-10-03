--[[
  tools/test/run.lua - run ByteOS's test suite on a PC

    lua tools/test/run.lua            every case in tools/test/cases/
    lua tools/test/run.lua shell      only cases whose name contains "shell"
    lua tools/test/run.lua -v         also list the tests that pass

  Each case runs in its own Lua process on a fresh copy of the OS (a temp
  directory), booted by tools/test/boot.lua. Needs Lua 5.3+, openssl and
  a POSIX shell; no internet, no Minecraft. Exits with 1 if anything fails.
]]--

local here = (arg[0]:match("^(.*)/[^/]*$")) or "."
local repo = here .. "/../.."
local function q(p) return "'" .. p:gsub("'", "'\\''") .. "'" end

local verbose, filter = false, nil
for _, a in ipairs(arg) do
  if a == "-v" then verbose = true else filter = a end
end

local cases = {}
local h = io.popen("ls -1 " .. q(here .. "/cases") .. " 2>/dev/null")
for f in h:lines() do
  if f:match("%.lua$") and (not filter or f:find(filter, 1, true)) then cases[#cases + 1] = f end
end
h:close()
table.sort(cases)
if #cases == 0 then print("no test cases found"); os.exit(1) end

local lua = arg[-1] or "lua"
local passed, failed, broken = 0, 0, {}
for _, c in ipairs(cases) do
  local tmp = io.popen("mktemp -d"):read("l")
  os.execute(("cd %s && cp -r init.lua boot sbin lib bin etc home var %s/ && mkdir -p %s/tmp"):format(q(repo), q(tmp), q(tmp)))
  os.execute(("[ -d %s/usr ] && cp -r %s/usr %s/"):format(q(repo), q(repo), q(tmp)))
  local out = io.popen(("%s %s %s %s 2>&1"):format(q(lua), q(here .. "/boot.lua"), q(tmp), q(here .. "/cases/" .. c)))
  local name = c:gsub("%.lua$", "")
  local p, f, extra = 0, 0, {}
  for line in out:lines() do
    if line:match("^PASS ") then
      p = p + 1
      if verbose then print("  ok    " .. name .. ": " .. line:sub(6)) end
    elseif line:match("^FAIL ") then
      f = f + 1
      print("  FAIL  " .. name .. ": " .. line:sub(6))
    elseif line:match("^     ") then
      print(line)
    else
      extra[#extra + 1] = line
    end
  end
  local okExit = out:close()
  if not okExit and f == 0 then
    f = 1
    print("  FAIL  " .. name .. ": the case crashed")
    for _, l in ipairs(extra) do print("        " .. l) end
  end
  print(("%-12s %3d passed%s"):format(name, p, f > 0 and (", " .. f .. " FAILED") or ""))
  passed, failed = passed + p, failed + f
  if f > 0 then broken[#broken + 1] = name end
  os.execute("rm -rf " .. q(tmp))
end
print(("\n%d passed, %d failed%s"):format(passed, failed, #broken > 0 and (" (" .. table.concat(broken, ", ") .. ")") or ""))
os.exit(failed == 0 and 0 or 1)
