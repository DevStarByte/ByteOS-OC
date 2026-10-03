--[[
  /lib/bpk.lua - ByteOS packages: .bpk archives, package info and databases

  Used by pacman, makepkg and tools/mkrepo.lua (which runs on a PC with a
  plain Lua 5.3+ interpreter, so nothing here may depend on ByteOS).

  ---- Archive (.bpk) ---------------------------------------------------------
      BPK1                        magic line
      <size> <flag> <name>        entry header
      <size bytes>                entry data, raw and binary-safe
      ...                         more entries until the end of the file

    flag  "-" stored as is, "z" LZW-compressed with lib/compress.lua
          (<size> is always the stored size)
    name  ".PKGINFO" first, then ".INSTALL" if the package has hooks, then
          every file by its absolute install path ("/usr/bin/hello.lua")

  ---- Package info (.PKGINFO, local desc, database entries) -----------------
    "key = value" lines. List fields repeat their key, one value per line:
      name = hello
      version = 1.0.0-1           pkgver-pkgrel, see bpk.vercmp
      desc = a friendly greeter
      depend = lolcat             (list)
      conflict = oldhello         (list)
      backup = /etc/hello.conf    (list) config files: user edits survive
      isize = 196                 installed size in bytes

    depend and conflict may carry a version: foo>=1.2, foo<2, foo=1.0-1.

    A repository database (<repo>.db) is one such block per package,
    separated by blank lines, with more fields:
      filename = hello-1.0.0-1.bpk
      csize = 312                 archive size in bytes
      crc32 = 1a2b3c4d            CRC-32 of the archive
      sha256 = ...                SHA-256 of the archive
    <repo>.db.sig, when present, is an ECDSA (P-256, SHA-256) signature of
    the database made with the repository's private key.

  ---- Package source (built by makepkg / tools/mkrepo.lua) -------------------
      <dir>/PKGBUILD.lua          return { name, version, rel, desc, url,
                                           depends, conflicts, backup, install }
      <dir>/<install>             optional hooks, e.g. hello.install:
                                    function post_install(version) end
                                    function post_upgrade(new, old) end
                                    function pre_remove(version) end
                                    function post_remove(version) end
      <dir>/files/...             the files, laid out as on the target disk
]]--

-- lib/compress.lua (19 KiB) is loaded only for compressed entries
local function compress() return require("compress") end

local bpk = {}

local MAGIC = "BPK1"
bpk.EXT = ".bpk"

-- ---- CRC-32 ----------------------------------------------------------------
local CRC = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do
    if c & 1 == 1 then c = 0xEDB88320 ~ (c >> 1) else c = c >> 1 end
  end
  CRC[i] = c
end

-- CRC-32 of `s`; pass the previous result as `crc` to checksum in pieces.
function bpk.crc32(s, crc)
  local c = (crc or 0) ~ 0xFFFFFFFF
  for i = 1, #s do
    c = CRC[(c ~ s:byte(i)) & 0xFF] ~ (c >> 8)
  end
  return c ~ 0xFFFFFFFF
end

function bpk.hex(crc) return ("%08x"):format(crc) end

-- ---- Versions --------------------------------------------------------------
-- Compares "pkgver-pkgrel" strings: -1 if a is older than b, 0, or 1.
-- Runs of digits compare as numbers, runs of letters alphabetically, a
-- number beats a letter run, and a version with more parts left is newer
-- (1.0.1 > 1.0). The pkgrel only counts when both sides have one.
local function split(v)
  local ver, rel = v:match("^(.-)%-(%d+)$")
  if ver then return ver, tonumber(rel) end
  return v, nil
end

local function cmpver(a, b)
  local ia, ib = 1, 1
  while true do
    ia, ib = a:find("%w", ia), b:find("%w", ib)
    if not ia or not ib then
      if ia then return 1 elseif ib then return -1 end
      return 0
    end
    local da, db = a:find("^%d", ia) ~= nil, b:find("^%d", ib) ~= nil
    if da ~= db then return da and 1 or -1 end
    local pat = da and "^%d+" or "^%a+"
    local sa, sb = a:match(pat, ia), b:match(pat, ib)
    if da then
      local x, y = tonumber(sa), tonumber(sb)
      if x ~= y then return x > y and 1 or -1 end
    elseif sa ~= sb then
      return sa > sb and 1 or -1
    end
    ia, ib = ia + #sa, ib + #sb
  end
end

function bpk.vercmp(a, b)
  local va, ra = split(a)
  local vb, rb = split(b)
  local c = cmpver(va, vb)
  if c ~= 0 or not ra or not rb then return c end
  if ra == rb then return 0 end
  return ra > rb and 1 or -1
end

-- ---- Package info ----------------------------------------------------------
local LISTS  = { depend = true, conflict = true, backup = true }
local FIELDS = { "name", "version", "desc", "url", "depend", "conflict", "backup",
                 "isize", "filename", "csize", "crc32", "sha256" }

function bpk.parseInfo(text)
  local info = { depend = {}, conflict = {}, backup = {} }
  for line in (text or ""):gmatch("[^\r\n]+") do
    local key, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key and LISTS[key] then
      if v ~= "" then table.insert(info[key], v) end
    elseif key then
      info[key] = v
    end
  end
  return info
end

function bpk.formatInfo(info)
  local out = {}
  for _, key in ipairs(FIELDS) do
    local v = info[key]
    if type(v) == "table" then
      for _, x in ipairs(v) do out[#out + 1] = key .. " = " .. x end
    elseif v ~= nil and v ~= "" then
      out[#out + 1] = key .. " = " .. tostring(v)
    end
  end
  return table.concat(out, "\n") .. "\n"
end

-- A database is a list of info blocks separated by blank lines.
function bpk.parseDb(text)
  local list, block = {}, {}
  local function flush()
    if #block > 0 then
      local info = bpk.parseInfo(table.concat(block, "\n"))
      if info.name then list[#list + 1] = info end
      block = {}
    end
  end
  for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^%s*$") then flush() else block[#block + 1] = line end
  end
  flush()
  return list
end

function bpk.formatDb(list)
  local out = {}
  for _, info in ipairs(list) do out[#out + 1] = bpk.formatInfo(info) end
  return table.concat(out, "\n")
end

-- ---- Reading archives ------------------------------------------------------
-- `h` is anything with h:read(n) -> string|nil (a ByteOS or io file).
function bpk.open(h)
  local r = { buf = "" }

  local function more(n)
    local c = h:read(math.max(n or 0, 4096))
    if not c or c == "" then return false end
    r.buf = r.buf .. c
    return true
  end

  local function line()
    while true do
      local i = r.buf:find("\n", 1, true)
      if i then
        local l = r.buf:sub(1, i - 1)
        r.buf = r.buf:sub(i + 1)
        return l
      end
      if not more() then
        if r.buf == "" then return nil end
        local l = r.buf; r.buf = ""
        return l
      end
    end
  end

  -- Next entry header: name, flag, size; nil at the end of the archive.
  function r.next()
    local l = line()
    if not l then return nil end
    local size, flag, name = l:match("^(%d+) ([%-z]) (.+)$")
    if not size then return nil, "corrupt package entry" end
    return name, flag, tonumber(size)
  end

  -- Hand the next `size` bytes to sink(chunk), or skip them without a sink.
  function r.stream(size, sink)
    while size > 0 do
      if r.buf == "" and not more(size) then return nil, "package is truncated" end
      local take = math.min(size, #r.buf)
      if sink then sink(r.buf:sub(1, take)) end
      r.buf = r.buf:sub(take + 1)
      size = size - take
    end
    return true
  end

  -- The whole entry as a string, decompressed.
  function r.read(flag, size)
    local parts = {}
    local ok, e = r.stream(size, function(c) parts[#parts + 1] = c end)
    if not ok then return nil, e end
    local data = table.concat(parts)
    if flag == "z" then
      local okd, plain = pcall(compress().decode, data)
      if not okd or not plain then return nil, "cannot decompress entry" end
      data = plain
    end
    return data
  end

  if line() ~= MAGIC then return nil, "not a ByteOS package (.bpk)" end
  return r
end

-- Install paths must be absolute and plain: no "..", ".", or empty parts.
function bpk.validPath(p)
  if type(p) ~= "string" or p:sub(1, 1) ~= "/" or p:sub(-1) == "/" then return false end
  for part in p:sub(2):gmatch("[^/]*") do
    if part == "" or part == "." or part == ".." then return false end
  end
  return not p:find("[%c]")
end

-- Reads the archive index: info, hooks and the file list, skipping the
-- file data. `h` is a fresh handle on the archive.
function bpk.inspect(h)
  local r, e = bpk.open(h)
  if not r then return nil, e end
  local name, flag, size = r.next()
  if name ~= ".PKGINFO" then return nil, "package has no .PKGINFO" end
  local text; text, e = r.read(flag, size)
  if not text then return nil, e end
  local pkg = { info = bpk.parseInfo(text), files = {}, order = {} }
  if not pkg.info.name or not pkg.info.version then
    return nil, ".PKGINFO lacks a name or version"
  end
  while true do
    name, flag, size = r.next()
    if not name then
      if flag then return nil, flag end
      return pkg
    end
    if name == ".INSTALL" then
      pkg.install, e = r.read(flag, size)
      if not pkg.install then return nil, e end
    elseif not bpk.validPath(name) then
      return nil, "unsafe path in package: " .. name
    else
      pkg.files[name] = { flag = flag, size = size }
      pkg.order[#pkg.order + 1] = name
      local ok; ok, e = r.stream(size)
      if not ok then return nil, e end
    end
  end
end

-- ---- Writing archives ------------------------------------------------------
-- Writes `entries` ({ name =, data = } in order) to h:write(). Entries of
-- 512 bytes or more are compressed when that saves at least 10 %.
function bpk.write(h, entries)
  h:write(MAGIC .. "\n")
  for _, e in ipairs(entries) do
    assert(not e.name:find("\n"), "entry name contains a newline")
    local data, flag = e.data, "-"
    if #data >= 512 then
      local z = compress().encode(data)
      if #z < #data * 0.9 then data, flag = z, "z" end
    end
    h:write(("%d %s %s\n"):format(#data, flag, e.name))
    h:write(data)
  end
end

-- ---- Building from source --------------------------------------------------
-- Builds the archive entries for the package source in `dir`.
-- `fsx` gives file access: readAll(path), list(dir) (directory names end in
-- "/"), isDirectory(path). Returns entries, info or nil, reason.
function bpk.build(dir, fsx)
  local src = fsx.readAll(dir .. "/PKGBUILD.lua")
  if not src then return nil, dir .. "/PKGBUILD.lua not found" end
  local fn, e = load(src, "=" .. dir .. "/PKGBUILD.lua", "t", {})
  if not fn then return nil, e end
  local ok, t = pcall(fn)
  if not ok or type(t) ~= "table" then return nil, "PKGBUILD.lua must return a table" end

  if type(t.name) ~= "string" or not t.name:match("^[%w][%w%-_.+]*$") then
    return nil, "PKGBUILD: bad or missing name"
  end
  if type(t.version) ~= "string" or not t.version:match("^[%w.+_]+$") then
    return nil, "PKGBUILD: bad or missing version (letters, digits and dots, no '-')"
  end
  local rel = tonumber(t.rel or 1)
  if not rel or rel < 1 or rel % 1 ~= 0 then return nil, "PKGBUILD: rel must be a whole number >= 1" end
  local info = {
    name = t.name, version = t.version .. "-" .. math.floor(rel),
    desc = t.desc or "", url = t.url,
    depend = t.depends or {}, conflict = t.conflicts or {}, backup = t.backup or {},
  }

  -- collect files/ recursively
  local files, paths = {}, {}
  local function walk(real, path)
    for _, n in ipairs(fsx.list(real) or {}) do
      local clean = n:gsub("/$", "")
      local r_, p = real .. "/" .. clean, path .. "/" .. clean
      if fsx.isDirectory(r_) then
        walk(r_, p)
      else
        local data = fsx.readAll(r_)
        if not data then error("cannot read " .. r_, 0) end
        if p:match("%.lua$") then
          local okc, perr = load(data, "=" .. p, "t", {})
          if not okc then error(("%s does not compile: %s"):format(p, perr), 0) end
        end
        files[p] = data
        paths[#paths + 1] = p
      end
    end
  end
  if not fsx.isDirectory(dir .. "/files") then return nil, dir .. "/files/ not found" end
  local okw, werr = pcall(walk, dir .. "/files", "")
  if not okw then return nil, werr end
  if #paths == 0 then return nil, "package has no files" end
  table.sort(paths)

  local isize = 0
  for _, p in ipairs(paths) do isize = isize + #files[p] end
  info.isize = isize
  for _, b in ipairs(info.backup) do
    if not files[b] then return nil, "backup file " .. b .. " is not in files/" end
  end

  local entries = { { name = ".PKGINFO", data = bpk.formatInfo(info) } }
  if t.install then
    local hooks = fsx.readAll(dir .. "/" .. t.install)
    if not hooks then return nil, "install file " .. t.install .. " not found" end
    local okh, herr = load(hooks, "=" .. t.install, "t", {})
    if not okh then return nil, herr end
    entries[#entries + 1] = { name = ".INSTALL", data = hooks }
  end
  for _, p in ipairs(paths) do entries[#entries + 1] = { name = p, data = files[p] } end
  return entries, info
end

-- "<name>-<version>.bpk"
function bpk.filename(info) return info.name .. "-" .. info.version .. bpk.EXT end

return bpk
