--[[
  /lib/pacman/sync.lua - pacman: downloading, repository signatures and pacman -Sy

  A part of /bin/pacman.lua, loaded into the same run when one of its
  functions is first needed (see PARTS there); P is shared by all parts.
]]--
local fs, bpk, T = k.fs, require("bpk"), term.theme
local CONF_PATH, LOCAL_DIR, SYNC_DIR, CACHE_DIR = P.CONF_PATH, P.LOCAL_DIR, P.SYNC_DIR, P.CACHE_DIR

-- Copy <server>/<name> into the file `dest`. A server is a URL (through the
-- internet card) or a directory. Returns size, crc32 or nil, reason.
local function download(server, name, dest, onBytes)
  local src = server .. "/" .. name
  local out = fs.open(dest, "w")
  if not out then return nil, "cannot write " .. dest end
  local size, crc = 0, 0
  local function sink(c)
    out:write(c)
    size = size + #c
    crc = bpk.crc32(c, crc)
    if onBytes then onBytes(size) end
  end
  local ok, e
  if src:match("^https?://") then
    local internet = require("internet")
    if internet.available() then ok, e = internet.get(src, sink)
    else ok, e = nil, "no internet card" end
  elseif fs.exists(src) then
    local h = fs.open(src, "r")
    while true do
      local c = h:read(4096)
      if not c then break end
      sink(c)
    end
    h:close()
    ok = true
  else
    ok, e = nil, "not found"
  end
  out:close()
  if not ok then fs.remove(dest); return nil, tostring(e) .. " (" .. src .. ")" end
  return size, crc
end
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64decode(s)
  local map = {}
  for i = 1, 64 do map[B64:sub(i, i)] = i - 1 end
  local out, bits, n = {}, 0, 0
  for c in s:gsub("[^%w%+/]", ""):gmatch(".") do
    bits, n = (bits << 6) | map[c], n + 6
    if n >= 8 then
      n = n - 8
      out[#out + 1] = string.char((bits >> n) & 0xFF)
      bits = bits & ((1 << n) - 1)
    end
  end
  return table.concat(out)
end

-- true, or nil and "nocard" or a reason the signature does not hold
local function verifySignature(data, sig, keyPath)
  local addr = component.list("data")()
  local dc = addr and component.proxy(addr)
  if not (dc and dc.ecdsa and dc.deserializeKey) then return nil, "nocard" end
  local pub = P.readIf(keyPath)
  if not pub then return nil, "no trusted key at " .. keyPath end
  local okKey, key = pcall(dc.deserializeKey, b64decode(pub), "ec-public")
  if not okKey or not key then return nil, "cannot read the trusted key " .. keyPath end
  local okV, valid = pcall(dc.ecdsa, data, key, sig)
  if okV and valid == true then return true end
  return nil, "the signature is invalid; the database may have been tampered with"
end

-- ---- GitHub servers ------------------------------------------------------------
-- raw.githubusercontent.com keeps a branch's files cached for minutes, so
-- right after a push a database could come from before it and point to
-- packages that are gone. A branch URL is therefore pinned to the
-- branch's newest P.commit (asked from the GitHub API); the database, its
-- signature and later the packages all come from that one commit. Without
-- an answer from the API the branch URL is used as it is.
local pins = {}
local function pinServer(server)
  local owner, repo, branch, rest = server:match("^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)(.*)$")
  if not owner or (#branch == 40 and branch:match("^%x+$")) then return server end
  local key = owner .. "/" .. repo .. "/" .. branch
  if pins[key] == nil then
    pins[key] = false
    local okI, internet = pcall(require, "internet")
    if okI and internet.available() then
      local body = internet.fetch(("https://api.github.com/repos/%s/%s/commits/%s"):format(owner, repo, branch),
        { Accept = "application/vnd.github.sha" })
      local sha = body and body:match("^%s*(%x+)%s*$")
      if sha and #sha == 40 then pins[key] = sha end
    end
  end
  if not pins[key] then return server end
  return ("https://raw.githubusercontent.com/%s/%s/%s%s"):format(owner, repo, pins[key], rest)
end

local warnedNoCard = false
local function checkSignature(name, conf, dbPath, server)
  local opts = P.readRepos().options or {}
  local level = ((conf.SigLevel or opts.SigLevel or "Optional"):match("%a+")) or "Optional"
  if level == "Never" then return true end
  local sigPath = dbPath .. ".sig"
  if not download(server or conf.Server, name .. ".db.sig", sigPath) then
    if level == "Required" then return nil, "the database is not signed (SigLevel = Required)" end
    return true
  end
  local ok, why = verifySignature(P.readIf(dbPath) or "", P.readIf(sigPath) or "",
    opts.TrustedKey or "/etc/pacman.d/byteos.pub")
  fs.remove(sigPath)
  if ok then return true end
  if why == "nocard" then
    if level == "Required" then
      return nil, "signatures need a tier 3 data card to be checked (SigLevel = Required)"
    end
    if not warnedNoCard then
      P.warn("package signatures are not checked: no tier 3 data card")
      warnedNoCard = true
    end
    return true
  end
  return nil, why
end

local function syncRepo(name, conf)
  local dest = SYNC_DIR .. "/" .. name .. ".db"
  -- databases from before .bpk lived in <sync>/<repo>/repo.db
  if fs.isDirectory(SYNC_DIR .. "/" .. name) then fs.remove(SYNC_DIR .. "/" .. name) end
  local server = pinServer(conf.Server)
  local size, e = download(server, name .. ".db", dest .. ".part")
  if not size then
    P.err("failed to synchronize " .. name .. ": " .. e)
    return false
  end
  local signed, why = checkSignature(name, conf, dest .. ".part", server)
  if not signed then
    fs.remove(dest .. ".part")
    P.err(name .. ": " .. why)
    return false, "signature"
  end
  if P.readIf(dest) == P.readIf(dest .. ".part") then
    fs.remove(dest .. ".part")
    term.cwrite(T.fg, " " .. name)
    term.cwrite(T.muted, " is up to date\n")
  else
    if fs.exists(dest) then fs.remove(dest) end
    fs.rename(dest .. ".part", dest)
    P.progress(name, 1); term.write("\n")
  end
  -- where this database came from: its packages are fetched from there
  fs.writeAll(dest .. ".server", conf.Server .. "\n" .. server .. "\n")
  return true
end

local function sync()
  P.header("Synchronizing package databases...")
  local names, repos = P.repoNames()
  local ok, onlySignatures = #names > 0, true
  for _, name in ipairs(names) do
    local done, why = syncRepo(name, repos[name])
    if not done then ok = false; onlySignatures = onlySignatures and why == "signature" end
  end
  P.forgetDb()
  if not ok and not onlySignatures then
    -- the usual cause: an old pacman.conf that -Syu kept next to a new one
    if fs.exists(CONF_PATH .. ".new") then
      P.warn("a newer config was saved as " .. CONF_PATH .. ".new; to use it run")
      term.cwrite(T.blue, "    mv " .. CONF_PATH .. ".new " .. CONF_PATH .. "\n")
    else
      P.warn("check the Server lines in " .. CONF_PATH)
    end
  end
  return ok
end

P.download = download
P.b64decode = b64decode
P.verifySignature = verifySignature
P.pinServer = pinServer
P.checkSignature = checkSignature
P.syncRepo = syncRepo
P.sync = sync
