--[[
  tar - pack files into one archive, list an archive, unpack it

    tar -cf ARCHIVE PATH...   pack the files and directories into ARCHIVE
    tar -tf ARCHIVE [NAME...] list what is in it (only NAME...)
    tar -xf ARCHIVE [NAME...] unpack it here (only NAME..., and what is
                              inside a directory named so)
      -v        name every file (with -t also its mode, owner, size, date)
      -C DIR    work in DIR: -c takes the paths from there, -x unpacks there
      -f -      the archive comes from / goes into a pipe
      -z        gzip it (.tar.gz); needs the gzip package. Packed
                archives are recognized when listing and unpacking
                anyway: tar -xf notes.tar.gz

  The letters may be joined and the dash left out: tar cvf notes.tar ~/notes.
  Archives are POSIX ustar, so tar on a PC opens them, and ByteOS opens
  theirs. Directories, files and symbolic links are kept with their mode,
  owner and group. Unpacking as root gives owners back, and a mode only
  where it is stricter than the place's default (a 600 file stays 600, a
  777 directory from /tmp does not make a home directory 777).
  A leading / is taken off the names, and a member with .. in its path is
  skipped, so an archive cannot write outside where it is unpacked.
  gzip (-z) is the only compression (no -j, -J).
]]--
local args = arg or {}
local clock = require("clock")
local rc = 0
local function fail(msg) shell.err("tar", msg); rc = 2 end
local function usage()
  term.write("usage: tar -c|-t|-x [-v] [-z] -f ARCHIVE [-C DIR] [PATH...]\n")
  return 2
end

-- ---- options ------------------------------------------------------------------
local mode, verbose, archive, dir, gz
local paths = {}
local i = 1
while i <= #args do
  local a = args[i]
  local letters = a:match("^%-(%a+)$") or (i == 1 and a:match("^(%a+)$"))
  if a == "--" then
    for j = i + 1, #args do paths[#paths + 1] = args[j] end
    break
  elseif letters then
    for c in letters:gmatch(".") do
      if c == "c" or c == "t" or c == "x" then
        if mode and mode ~= c then shell.err("tar", "only one of -c, -t and -x"); return 2 end
        mode = c
      elseif c == "v" then verbose = true
      elseif c == "f" or c == "C" then
        i = i + 1
        if not args[i] then shell.err("tar", "-" .. c .. " needs a name"); return 2 end
        if c == "f" then archive = args[i] else dir = args[i] end
      elseif c == "z" then gz = true
      elseif c == "j" or c == "J" or c == "a" then
        shell.err("tar", "only gzip compression (-z) is supported"); return 2
      else
        shell.err("tar", "unknown option -" .. c); return usage()
      end
    end
  else
    paths[#paths + 1] = a
  end
  i = i + 1
end
if not mode then return usage() end
if not archive then shell.err("tar", "no archive given (-f ARCHIVE, or -f - for a pipe)"); return 2 end

local base = shell.normalize(dir or ".")
if dir and not fs.isDirectory(base) then shell.err("tar", dir .. ": not a directory"); return 2 end
local function inBase(p)
  if p:sub(1, 1) == "/" then return shell.normalize(p) end
  return shell.normalize(base .. "/" .. p)
end
local archivePath = archive ~= "-" and shell.normalize(archive)

-- ---- users and groups by number (ustar keeps both) ------------------------------
local ids
local function idTables()
  if ids then return ids end
  ids = { uid = {}, gid = {}, user = {}, group = {} }
  for l in (fs.readAll("/etc/passwd") or ""):gmatch("[^\r\n]+") do
    local name, uid = l:match("^([^:]*):[^:]*:(%d+):")
    if name then ids.uid[name] = tonumber(uid); ids.user[tonumber(uid)] = name end
  end
  for l in (fs.readAll("/etc/group") or ""):gmatch("[^\r\n]+") do
    local name, gid = l:match("^([^:]*):[^:]*:(%d+):")
    if name then ids.gid[name] = tonumber(gid); ids.group[tonumber(gid)] = name end
  end
  return ids
end

-- ---- ustar headers ---------------------------------------------------------------
local ZERO = ("\0"):rep(512)
local function field(s, n) s = s:sub(1, n); return s .. ("\0"):rep(n - #s) end
local function oct(n, width) return ("%0" .. (width - 1) .. "o"):format(math.floor(n)) .. "\0" end
local function cstr(s) return s:match("^[^\0]*") end
local function num(s) return tonumber(s:match("^[ \0]*([0-7]*)"), 8) or 0 end
local function checksum(h)
  local sum = 0
  for j = 1, 512 do
    sum = sum + (j >= 149 and j <= 156 and 32 or h:byte(j))
  end
  return sum
end

-- name, kind ("0" file, "5" directory, "2" link), size, meta, mtime, link
local function header(name, kind, size, meta, mtime, link)
  local prefix = ""
  if #name > 100 then
    -- the start of a long name goes into the 155-byte prefix, cut at a /
    local cut
    for pos = 1, #name do
      if name:sub(pos, pos) == "/" and pos - 1 <= 155 and #name - pos <= 100 and pos < #name then cut = pos; break end
    end
    if not cut then return nil, "name too long" end
    prefix, name = name:sub(1, cut - 1), name:sub(cut + 1)
  end
  local t = idTables()
  local h = field(name, 100) .. oct(meta.mode, 8) .. oct(t.uid[meta.owner] or 0, 8) .. oct(t.gid[meta.group] or 0, 8)
    .. oct(size, 12) .. oct(mtime, 12) .. "        " .. kind .. field(link or "", 100) .. "ustar\0" .. "00"
    .. field(meta.owner, 32) .. field(meta.group, 32) .. oct(0, 8) .. oct(0, 8) .. field(prefix, 155) .. ("\0"):rep(12)
  return h:sub(1, 148) .. ("%06o\0 "):format(checksum(h)) .. h:sub(157)
end

local function mtimeOf(p)
  local proxy, sub = fs.resolve(p)
  if proxy and proxy.lastModified then
    local ok, ms = pcall(proxy.lastModified, sub)
    if ok and type(ms) == "number" and ms > 0 then return ms // 1000 end
  end
  return (clock.now())
end

local function modeString(kind, m)
  local s = { kind == "5" and "d" or kind == "2" and "l" or "-" }
  for shift = 6, 0, -3 do
    local b = (m >> shift) & 7
    s[#s + 1] = (b & 4 ~= 0 and "r" or "-") .. (b & 2 ~= 0 and "w" or "-") .. (b & 1 ~= 0 and "x" or "-")
  end
  return table.concat(s)
end

-- The gzip package's library, for -z (and archives that turn out packed).
local function loadDeflate()
  local ok, d = pcall(require, "deflate")
  if not ok then return nil, "tar -z needs the gzip package: pacman -S gzip" end
  package.loaded.deflate = nil -- gone from memory once tar ends
  return d
end

-- ---- create ----------------------------------------------------------------------
local function create()
  if #paths == 0 then shell.err("tar", "nothing to pack: give files or directories"); return 2 end
  local deflate
  if gz then
    local e
    deflate, e = loadDeflate()
    if not deflate then shell.err("tar", e); return 2 end
  end
  -- what is written goes out in pieces of a few KiB (each disk write is a
  -- component call)
  local sink, file
  if archive == "-" then
    if not (stdio and stdio.output) then
      shell.err("tar", "refusing to write an archive to the screen (use > or a pipe)"); return 2
    end
    sink = function(s) stdio.output[#stdio.output + 1] = s end
  else
    local e
    file, e = fs.open(archivePath, "w")
    if not file then shell.err("tar", archive .. ": " .. tostring(e)); return 2 end
    sink = function(s) file:write(s) end
  end
  local packer
  if deflate then
    packer = deflate.gzipStream(sink, { breathe = function() k.event.pull(0) end })
    sink = packer.write
  end
  local pending, size = {}, 0
  local function emit(s)
    pending[#pending + 1] = s; size = size + #s
    if size >= 4096 then sink(table.concat(pending)); pending, size = {}, 0 end
  end
  local function padTo(n) if n % 512 > 0 then emit(("\0"):rep(512 - n % 512)) end end

  local warned = false
  local function add(real, name)
    if real == archivePath then term.write("tar: " .. name .. ": the archive itself, skipped\n"); return end
    local link = fs.readlink and fs.readlink(real)
    if not link and not fs.exists(real) then fail(name .. ": no such file or directory"); return end
    local meta = fs.stat(real)
    local isDir = not link and fs.isDirectory(real)
    local kind = link and "2" or isDir and "5" or "0"
    local fsize = kind == "0" and fs.size(real) or 0
    local src
    if kind == "0" then
      local e
      src, e = fs.open(real, "r")
      if not src then fail(name .. ": " .. tostring(e)); return end
    end
    local h, e = header(isDir and name .. "/" or name, kind, fsize,
      link and { mode = 511, owner = meta.owner, group = meta.group } or meta, mtimeOf(real), link)
    if not h then fail(name .. ": " .. e); if src then src:close() end return end
    emit(h)
    if verbose then term.write(name .. (isDir and "/" or "") .. "\n") end
    if src then
      local left = fsize
      while left > 0 do
        local chunk = src:read(math.min(left, 4096))
        if not chunk then break end
        if #chunk > left then chunk = chunk:sub(1, left) end
        emit(chunk); left = left - #chunk
      end
      src:close()
      if left > 0 then emit(("\0"):rep(left)); fail(name .. ": file shrank while packing") end
      padTo(fsize)
    elseif isDir then
      for _, entry in ipairs(fs.list(real) or {}) do
        local n = entry:gsub("/$", "")
        add((real == "/" and "" or real) .. "/" .. n, name == "." and n or (name .. "/" .. n))
      end
    end
  end

  for _, p in ipairs(paths) do
    local name = p:gsub("/+", "/")
    if #name > 1 then name = name:gsub("/$", "") end
    if name:sub(1, 1) == "/" then
      if not warned then term.write("tar: removing leading '/' from member names\n"); warned = true end
      name = name:gsub("^/+", "")
      if name == "" then name = "." end
    end
    add(inBase(p), name)
  end
  emit(ZERO); emit(ZERO)
  if size > 0 then sink(table.concat(pending)) end
  if packer then packer.finish() end
  if file then file:close() end
  return rc
end

-- ---- reading an archive --------------------------------------------------------------
local function reader()
  local nextChunk
  if archive == "-" then
    local all = stdin.read("a") or ""
    nextChunk = function() local c = all; all = nil; return c end
  else
    local f, e = fs.open(archivePath, "r")
    if not f or fs.isDirectory(archivePath) then return nil, archive .. ": " .. tostring(e or "a directory") end
    nextChunk = function()
      local c = f:read(math.huge)
      if not c then f:close() end
      return c
    end
  end
  -- a .tar.gz (with -z, or seen by its first bytes): unpacked on the way,
  -- piece by piece; gunzip hands its pieces over through a coroutine
  local first = nextChunk()
  local pushed = first
  local function raw()
    if pushed then local c = pushed; pushed = nil; return c end
    return nextChunk()
  end
  local fetch = raw
  if first and (gz or first:sub(1, 2) == "\31\139") then
    local deflate, e = loadDeflate()
    if not deflate then return nil, e end
    local done = false
    local unpack = coroutine.wrap(function()
      local ok, err = deflate.gunzip(raw, function(s) coroutine.yield(s) end)
      if not ok then error(archive .. ": " .. err, 0) end
    end)
    fetch = function()
      if done then return nil end
      local c = unpack()
      if c == nil then done = true end
      return c
    end
  end
  nextChunk = fetch
  local buf, pos, eof = "", 1, false
  return function(n)
    while #buf - pos + 1 < n and not eof do
      local c = nextChunk()
      if c then buf = buf:sub(pos) .. c; pos = 1 else eof = true end
    end
    local s = buf:sub(pos, pos + n - 1)
    pos = pos + #s
    return s
  end
end

-- Calls fn(entry, data) for every member; data(sink) passes its contents
-- in pieces to sink (or skips them without one).
local function walk(fn)
  local read, e = reader()
  if not read then shell.err("tar", e); return 2 end
  local long, pax = nil, {}
  while true do
    local h = read(512)
    if h == "" or h == ZERO then break end
    if #h < 512 then fail("unexpected end of the archive"); break end
    if checksum(h) ~= num(h:sub(149, 156)) then fail("this does not look like a tar archive"); break end
    local entry = {
      name = cstr(h:sub(1, 100)), mode = num(h:sub(101, 108)), uid = num(h:sub(109, 116)), gid = num(h:sub(117, 124)),
      size = num(h:sub(125, 136)), mtime = num(h:sub(137, 148)), kind = h:sub(157, 157), link = cstr(h:sub(158, 257)),
    }
    if h:sub(258, 262) == "ustar" then
      entry.owner, entry.group = cstr(h:sub(266, 297)), cstr(h:sub(298, 329))
      local prefix = cstr(h:sub(346, 500))
      if prefix ~= "" then entry.name = prefix .. "/" .. entry.name end
    end
    if entry.kind == "\0" then entry.kind = "0" end
    local left, padding = entry.size, (512 - entry.size % 512) % 512
    local function data(sink)
      while left > 0 do
        local chunk = read(math.min(left, 4096))
        if chunk == "" then fail("unexpected end of the archive"); left = 0; break end
        left = left - #chunk
        if sink then sink(chunk) end
      end
      read(padding); padding = 0
    end
    if entry.kind == "L" or entry.kind == "x" or entry.kind == "g" or entry.kind == "K" then
      -- long names (GNU) and extended headers (pax) for the next member
      local parts = {}
      data(function(c) parts[#parts + 1] = c end)
      local text = table.concat(parts)
      if entry.kind == "L" then long = cstr(text)
      elseif entry.kind == "x" then
        for key, value in text:gmatch("%d+ ([^=]+)=([^\n]*)\n") do
          if key == "path" then pax.name = value elseif key == "linkpath" then pax.link = value end
        end
      end
    else
      entry.name = pax.name or long or entry.name
      entry.link = pax.link or entry.link
      long, pax = nil, {}
      if entry.kind == "5" then entry.name = entry.name:gsub("/+$", "") end
      fn(entry, data)
      data() -- whatever fn did not read
    end
  end
  return rc
end

-- ---- list ------------------------------------------------------------------------
local function list()
  return walk(function(entry)
    local name = entry.name .. (entry.kind == "5" and "/" or "")
    if not verbose then term.write(name .. "\n"); return end
    local t = idTables()
    local owner = entry.owner and entry.owner ~= "" and entry.owner or t.user[entry.uid] or tostring(entry.uid)
    local group = entry.group and entry.group ~= "" and entry.group or t.group[entry.gid] or tostring(entry.gid)
    term.write(("%s %s/%s %8d %s %s%s\n"):format(modeString(entry.kind, entry.mode), owner, group, entry.size,
      clock.date("%F %H:%M", entry.mtime), name, entry.kind == "2" and (" -> " .. entry.link) or ""))
  end)
end

-- ---- extract ---------------------------------------------------------------------
local function mkdirs(p)
  if fs.isDirectory(p) then return true end
  local parent = p:match("^(.*)/[^/]+$")
  if parent and parent ~= "" then mkdirs(parent) end
  return fs.makeDirectory(p)
end

local function extract()
  local root = k.user() == "root"
  local warned = false
  local function restore(path, entry)
    if not root then return end
    local st, t = fs.stat(path), idTables()
    local owner = entry.owner and entry.owner ~= "" and entry.owner or t.user[entry.uid]
    local group = entry.group and entry.group ~= "" and entry.group or t.group[entry.gid]
    if not t.uid[owner] then owner = nil end
    if not t.gid[group] then group = nil end
    if (owner and owner ~= st.owner) or (group and group ~= st.group) then fs.chown(path, owner, group) end
    -- only ever tighten: the default here may allow what the archive did not
    local m = entry.mode & 4095
    if st.mode & ~m ~= 0 then fs.chmod(path, m & st.mode) end
  end
  local function each(entry, data)
    local name = entry.name
    if name:sub(1, 1) == "/" then
      if not warned then term.write("tar: removing leading '/' from member names\n"); warned = true end
      name = name:gsub("^/+", "")
    end
    for seg in name:gmatch("[^/]+") do
      if seg == ".." then fail(entry.name .. ": has '..' in its path, skipped"); return end
    end
    if name == "" or name == "." then return end
    local dest = shell.normalize(base .. "/" .. name)
    if verbose then term.write(name .. (entry.kind == "5" and "/" or "") .. "\n") end
    local parent = dest:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and not fs.isDirectory(parent) then mkdirs(parent) end
    if entry.kind == "5" then
      if not fs.isDirectory(dest) and not mkdirs(dest) then fail(name .. ": cannot create directory"); return end
      restore(dest, entry)
    elseif entry.kind == "2" then
      if not fs.link then fail(name .. ": symbolic links are not supported here, skipped"); return end
      if fs.readlink(dest) or (fs.exists(dest) and not fs.isDirectory(dest)) then fs.remove(dest) end
      local ok, e = fs.link(entry.link, dest)
      if not ok then fail(name .. ": " .. tostring(e)) end
    elseif entry.kind == "0" or entry.kind == "7" or entry.kind == "1" then
      if fs.isDirectory(dest) and not (fs.readlink and fs.readlink(dest)) then fail(name .. ": a directory is in the way"); return end
      if fs.readlink and fs.readlink(dest) then fs.remove(dest) end
      local f, e = fs.open(dest, "w")
      if not f then fail(name .. ": " .. tostring(e)); return end
      if entry.kind == "1" then
        -- a hard link: a copy of the member it points to
        local text = fs.readAll(shell.normalize(base .. "/" .. entry.link:gsub("^/+", "")))
        if text then f:write(text) else fail(name .. ": link target " .. entry.link .. " not unpacked") end
      else
        data(function(c) f:write(c) end)
      end
      f:close()
      restore(dest, entry)
    else
      fail(name .. ": unsupported kind of member '" .. entry.kind .. "', skipped")
    end
  end
  if root and fs.permsBatch then
    return fs.permsBatch(walk, each)
  end
  return walk(each)
end

if mode == "c" then return create() end

-- With names after the archive, -t and -x only take those members (and
-- what is inside a named directory); a name not in the archive is an error.
if #paths > 0 then
  local want, found = {}, {}
  for _, p in ipairs(paths) do want[#want + 1] = (p:gsub("^/+", ""):gsub("/+$", "")) end
  local inner = walk
  walk = function(fn)
    return inner(function(entry, data)
      local name = entry.name:gsub("^/+", ""):gsub("/+$", "")
      for _, w in ipairs(want) do
        if name == w or name:sub(1, #w + 1) == w .. "/" then
          found[w] = true
          return fn(entry, data)
        end
      end
    end)
  end
  local result = mode == "t" and list() or extract()
  for _, w in ipairs(want) do
    if not found[w] then fail(w .. ": not found in the archive") end
  end
  return rc ~= 0 and rc or result
end
if mode == "t" then return list() end
return extract()
