--[[
  tools/test/boot.lua - boot ByteOS on a PC and run one test case

    lua tools/test/boot.lua <root> <case.lua>      (run.lua does this)

  <root> is a scratch copy of the OS. Its boot/kernel.lua is loaded on top
  of a fake OpenComputers machine: the boot disk is the <root> directory,
  extra disks can be plugged in, a tier 3 data card checks ECDSA with the
  openssl command line, and the screen is tools/test/fterm.lua.

  A case file calls the functions below; every result line printed is
  "PASS <name>" or "FAIL <name>: <why>" for run.lua to count.

    test(name, fn)               run fn; a failing check fails the test
    eq(got, want, what)  ok(cond, what)  has(text, part, what)  lacks(...)
    run(line) -> output, status  a command line in the shell (stdout and
                                 errors together), as the current user
    as(user, fn)                 fn as another user (kernel.runAs)
    users()                      root, alice (wheel), bob; passwords
                                 rootpw / alicepw / bobpw
    answers{...}  keys{...}      queue input for term.read / readKey
    signals{...}                 queue signals for computer.pullSignal
    deliver{...}                 the same, and have the kernel handle them now
    disk(dir, addr, label)       a filesystem component on a host dir
    useDatacard(true|false)      put a tier 3 data card in (or take it out)
    file(path)  put(path, data)  read/write the fake disk directly
    screen()                     what the terminal shows
    ROOT, REPO, kernel, shell, term
]]--

local ROOT, CASE = arg[1], arg[2]
local REPO = (arg[0]:match("^(.*)/tools/test/[^/]*$")) or "."
local function q(p) return "'" .. tostring(p):gsub("'", "'\\''") .. "'" end
local function sh(c) return os.execute(c) == true end

-- ---- the fake machine ------------------------------------------------------
local handles, nextH = {}, 1
local function fsProxy(root, addr, label)
  return {
    address = addr,
    getLabel = function() return label end,
    isReadOnly = function() return false end,
    exists = function(p) return sh("test -e " .. q(root .. p)) end,
    isDirectory = function(p) return sh("test -d " .. q(root .. p)) end,
    size = function(p) local f = io.open(root .. p, "rb"); if not f then return 0 end local n = f:seek("end"); f:close(); return n end,
    list = function(p)
      local t, h = {}, io.popen("ls -1Ap " .. q(root .. p) .. " 2>/dev/null")
      for l in h:lines() do t[#t + 1] = l end
      h:close()
      return t
    end,
    makeDirectory = function(p) return sh("mkdir -p " .. q(root .. p)) end,
    remove = function(p) if not sh("test -e " .. q(root .. p)) then return false end return sh("rm -rf " .. q(root .. p)) end,
    rename = function(a, b) return os.rename(root .. a, root .. b) ~= nil end,
    open = function(p, mode)
      local f = io.open(root .. p, (mode or "r"):sub(1, 1) .. "b")
      if not f then return nil, p end
      handles[nextH] = f; nextH = nextH + 1
      return nextH - 1
    end,
    read = function(h, n) local d = handles[h]:read(n == math.huge and "a" or math.min(n, 2048)); if d == "" then return nil end return d end,
    write = function(h, d) handles[h]:write(d); return true end,
    seek = function(h, w, o) return handles[h]:seek(w, o) end,
    close = function(h) handles[h]:close(); handles[h] = nil end,
    spaceTotal = function() return 4194304 end,
    spaceUsed = function()
      local h = io.popen("du -sb " .. q(root) .. " | cut -f1")
      local n = tonumber(h:read("a")) or 0
      h:close()
      return n
    end,
  }
end

local function tmpfile(data)
  local n = os.tmpname()
  local f = io.open(n, "wb"); f:write(data); f:close()
  return n
end

local datacard = {
  address = "datacard-0000",
  sha256 = function(d)
    local n = tmpfile(d)
    local h = io.popen("openssl dgst -sha256 -binary " .. q(n))
    local r = h:read("a"); h:close(); os.remove(n)
    return r
  end,
  deserializeKey = function(der, kind) assert(kind == "ec-public"); return { der = der } end,
  ecdsa = function(data, key, sig)
    local kd, dd, sd, kp = tmpfile(key.der), tmpfile(data), tmpfile(sig), os.tmpname()
    local ok = sh("openssl ec -pubin -inform DER -in " .. q(kd) .. " -out " .. q(kp) .. " 2>/dev/null && openssl dgst -sha256 -verify "
      .. q(kp) .. " -signature " .. q(sd) .. " " .. q(dd) .. " >/dev/null 2>&1")
    for _, n in ipairs({ kd, dd, sd, kp }) do os.remove(n) end
    return ok
  end,
}

local bootfs = fsProxy(ROOT, "bootfs00-test", "ByteOS")
local COMPONENTS = {
  ["bootfs00-test"] = { "filesystem", bootfs },
  ["drive999-test"] = { "drive", { address = "drive999-test", getLabel = function() end, getCapacity = function() return 1048576 end } },
}
local SIGNALS = {}

_G.component = {
  list = function(kind)
    local keys = {}
    for a, c in pairs(COMPONENTS) do if not kind or c[1] == kind then keys[#keys + 1] = a end end
    table.sort(keys)
    local i = 0
    return function() i = i + 1; return keys[i] end
  end,
  proxy = function(a) return COMPONENTS[a] and COMPONENTS[a][2] end,
}
_G.computer = {
  uptime = os.clock,
  pullSignal = function() return table.unpack(table.remove(SIGNALS, 1) or {}) end,
  totalMemory = function() return 196608 end, freeMemory = function() return 120000 end,
  tmpAddress = function() return "tmpfs000" end, address = function() return "computer" end,
  shutdown = function() error("shutdown requested", 0) end,
}
_G.bootfs = bootfs
_G.kprint = function() end
_G.BOOTLOG = { { t = 0, tag = "kernel", msg = "ByteOS test boot" } }

assert(loadfile(ROOT .. "/boot/kernel.lua", "t", _G))()
local term = dofile(REPO .. "/tools/test/fterm.lua")
_G.term = term
package.loaded.term = term
_G.PATH, _G.HOSTNAME, _G.USER, _G.HOME, _G.PWD = "/bin:/usr/bin:/sbin", "byteos", "root", "/home/root", "/"
local shell = require("shell")
_G.shell = shell
local kernel = _G.kernel

-- ---- the test API ----------------------------------------------------------
local current
local function fail(msg) error({ testFailure = msg }, 0) end

function test(name, fn)
  current = name
  local ok, e = pcall(fn)
  if ok then
    print("PASS " .. name)
  else
    local msg = type(e) == "table" and e.testFailure or ("error: " .. tostring(e))
    print("FAIL " .. name .. ": " .. tostring(msg):gsub("\n", "\n     "))
  end
  current = nil
end

local function show(v) return type(v) == "string" and ("%q"):format(v) or tostring(v) end
function eq(got, want, what)
  if got ~= want then fail((what or "value") .. ": got " .. show(got) .. ", want " .. show(want)) end
end
function ok(cond, what) if not cond then fail(what or "condition is false") end end
function has(text, part, what)
  if not tostring(text):find(part, 1, true) then fail((what or "output") .. " lacks " .. show(part) .. " in:\n" .. tostring(text)) end
end
function lacks(text, part, what)
  if tostring(text):find(part, 1, true) then fail((what or "output") .. " should not contain " .. show(part) .. " in:\n" .. tostring(text)) end
end

function run(line)
  local buf = {}
  shell.interrupted = false
  local prevSink = shell.errorSink()
  shell.setErrorSink(function(t) buf[#buf + 1] = t end)
  local okRun, rc = pcall(shell.withIO, { output = buf }, shell.execute, line)
  shell.setErrorSink(prevSink)
  if not okRun then error(rc, 0) end
  return table.concat(buf), rc
end

function as(user, fn)
  local prevPwd = _G.PWD
  return kernel.runAs(user, function()
    _G.PWD = _G.HOME
    local res = table.pack(pcall(fn))
    _G.PWD = prevPwd
    if not res[1] then error(res[2], 0) end
    return table.unpack(res, 2, res.n)
  end)
end

function file(path)
  local f = io.open(ROOT .. path, "rb")
  if not f then return nil end
  local d = f:read("a"); f:close()
  return d
end

function put(path, data)
  os.execute("mkdir -p " .. q((ROOT .. path):match("^(.*)/")))
  local f = assert(io.open(ROOT .. path, "wb")); f:write(data); f:close()
end

function users()
  put("/etc/passwd", "root:x:0:0:root:/home/root:/bin/sh\nalice:x:1000:100:alice:/home/alice:/bin/sh\nbob:x:1001:100:bob:/home/bob:/bin/sh\n")
  put("/etc/group", "root:x:0:root\nwheel:x:10:alice\nusers:x:100:\n")
  put("/etc/shadow", "root:rootpw:::::::\nalice:alicepw:::::::\nbob:bobpw:::::::\n")
  for _, u in ipairs({ "root", "alice", "bob" }) do os.execute("mkdir -p " .. q(ROOT .. "/home/" .. u)) end
end

function answers(list) term.answers(list) end
function keys(list) term.feed(list) end
function signals(list) for _, s in ipairs(list) do SIGNALS[#SIGNALS + 1] = s end end
-- queue signals and let the kernel handle all of them now
function deliver(list) signals(list); while #SIGNALS > 0 do kernel.event.pull(1) end end
function screen() return term.screen() end
function useDatacard(on) COMPONENTS["datacard-0000"] = on and { "data", datacard } or nil end

function disk(dir, addr, label)
  os.execute("mkdir -p " .. q(dir))
  COMPONENTS[addr] = { "filesystem", fsProxy(dir, addr, label) }
end
function undisk(addr) COMPONENTS[addr] = nil end

_G.ROOT, _G.REPO, _G.shell, _G.term = ROOT, REPO, shell, term

local fn, err = loadfile(CASE, "t", _G)
if not fn then print("FAIL loading " .. CASE .. ": " .. err); os.exit(1) end
local okCase, caseErr = pcall(fn)
if not okCase then print("FAIL " .. (current or CASE) .. ": crashed: " .. tostring(caseErr)); os.exit(1) end
