--[[
  tools/test/openos.lua - run install.lua as if under OpenOS, on a PC

    ANSWERS="2|1|/|1|yes|yes|no" NO_INTERNET=1 \
      lua tools/test/openos.lua install.lua <target dir> [<source dir>]

  Provides require("component") and require("computer"), answers io.read
  from ANSWERS (|-separated), and these components: a read-only OpenOS
  floppy (the running system), a tmpfs, the target disk (a directory), an
  optional source disk with the ByteOS files, an EEPROM holding the Lua
  BIOS and, unless NO_INTERNET is set, an internet card through curl.
]]--
local INSTALLER, TARGET, SOURCE = arg[1], arg[2], arg[3]
local function q(p) return "'" .. tostring(p):gsub("'", "'\\''") .. "'" end
local function sh(c) return os.execute(c) == true end
local handles, nextH = {}, 1
local function fsProxy(root, addr, label, ro)
  local lab = label
  return {
    address = addr, getLabel = function() return lab end, setLabel = function(l) lab = l; print("[label " .. addr:sub(1,8) .. " = " .. l .. "]") end,
    isReadOnly = function() return ro or false end,
    exists = function(p) return sh("test -e " .. q(root .. p)) end,
    isDirectory = function(p) return sh("test -d " .. q(root .. p)) end,
    size = function(p) local f = io.open(root .. p, "rb"); if not f then return 0 end local n = f:seek("end"); f:close(); return n end,
    list = function(p) local t, h = {}, io.popen("ls -1Ap " .. q(root .. p) .. " 2>/dev/null") for l in h:lines() do t[#t + 1] = l end h:close() return t end,
    makeDirectory = function(p) return sh("mkdir -p " .. q(root .. p)) end,
    remove = function(p) return sh("rm -rf " .. q(root .. p)) end,
    open = function(p, mode) local f = io.open(root .. p, (mode or "r"):sub(1, 1) .. "b"); if not f then return nil, p end handles[nextH] = f; nextH = nextH + 1; return nextH - 1 end,
    read = function(h, n) local d = handles[h]:read(math.min(n, 2048)); if d == "" then return nil end return d end,
    write = function(h, d) handles[h]:write(d); return true end,
    close = function(h) handles[h]:close() end,
    spaceTotal = function() return 2097152 end,
    spaceUsed = function() local h = io.popen("du -sb " .. q(root) .. " | cut -f1"); local n = tonumber(h:read("a")) or 0; h:close(); return n end,
  }
end
local eepromCode, eepromLabel, eepromData = "-- Lua BIOS\nlocal init", "EEPROM (Lua BIOS)", "openos00"
local scratch = os.tmpname()
os.remove(scratch)
os.execute("mkdir -p " .. q(scratch .. "/floppy") .. " " .. q(scratch .. "/tmpfs"))
local C = {
  ["openos00-floppy"] = { "filesystem", fsProxy(scratch .. "/floppy", "openos00-floppy", "openos", true) },
  ["tmpfs000-xxxx"] = { "filesystem", fsProxy(scratch .. "/tmpfs", "tmpfs000-xxxx", "tmpfs") },
  ["hdd00001-aaaa"] = { "filesystem", fsProxy(TARGET, "hdd00001-aaaa", nil) },
  ["eeprom00"] = { "eeprom", { get = function() return eepromCode end, set = function(c) eepromCode = c end,
      getLabel = function() return eepromLabel end, setLabel = function(l) eepromLabel = l end,
      getData = function() return eepromData end, setData = function(d) eepromData = d; print("[eeprom data = " .. d .. "]") end } },
}
if SOURCE then C["src00000-bbbb"] = { "filesystem", fsProxy(SOURCE, "src00000-bbbb", "byteos-src", true) } end
if not os.getenv("NO_INTERNET") then
  C["inet0000"] = { "internet", { request = function(url, _, headers)
    local out = os.tmpname()
    local hdr = ""
    for k, v in pairs(headers or {}) do hdr = hdr .. " -H " .. q(k .. ": " .. v) end
    local p = io.popen("curl -sL -o " .. q(out) .. " -w '%{http_code}'" .. hdr .. " " .. q(url))
    local code = tonumber(p:read("a")); p:close()
    local f = io.open(out, "rb")
    return { finishConnect = function() return true end, response = function() return code end,
             read = function(n) return f:read(n) end, close = function() f:close(); os.remove(out) end }
  end } }
end
package.loaded.component = {
  list = function(kind) local ks = {} for a, c in pairs(C) do if c[1] == kind then ks[#ks + 1] = a end end table.sort(ks) local i = 0 return function() i = i + 1 return ks[i] end end,
  proxy = function(a) return C[a] and C[a][2] end,
}
package.loaded.computer = { getBootAddress = function() return "openos00-floppy" end, setBootAddress = function(a) print("[boot address = " .. a .. "]") end,
  tmpAddress = function() return "tmpfs000-xxxx" end, shutdown = function(r) print("[shutdown, reboot=" .. tostring(r) .. "]") end }
local answers = {}
for a in (os.getenv("ANSWERS") or ""):gmatch("[^|]*") do answers[#answers + 1] = a end
local realRead = io.read
io.read = function() local a = table.remove(answers, 1); io.write((a or "<eof>") .. "\n"); return a end
local exitCode
os.exit = function(c) exitCode = c; error("__exit__", 0) end
local ok, e = pcall(dofile, INSTALLER)
if not ok and e ~= "__exit__" then print("CRASH: " .. tostring(e)) end
print(("[eeprom: label=%s, ByteBIOS=%s]"):format(eepromLabel, tostring(eepromCode:find("ByteBIOS", 1, true) ~= nil)))
os.execute("rm -rf " .. q(scratch))
