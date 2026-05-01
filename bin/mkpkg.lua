--[[
  mkpkg - build / convert ByteOS package files

  Usage:
    mkpkg <input.pkg>            -> writes <input>.pkg.z next to it
    mkpkg <input.pkg> <out.pkg.z>
    mkpkg -d <input.pkg.z>       -> writes a decompressed <input>.pkg

  A `.pkg.z` file is a regular Lua source file that returns a package table
  with `format = "lzw1"`. Each entry in `files` is a base64-encoded LZW
  stream produced by lib/compress.lua. pacman transparently decompresses it
  during install.
]]--

local fs       = k.fs
local args     = arg or {}
local compress = require("compress")

local function info(msg, color)
  term.setForeground(color or 0x55FF55); term.write(":: ")
  term.setForeground(0xFFFFFF); term.write(msg .. "\n")
end

local function err(msg)
  term.setForeground(0xFF5555); term.write("error: ")
  term.setForeground(0xFFFFFF); term.write(msg .. "\n")
end

local function loadPkg(path)
  local src = fs.readAll(path)
  if not src then err("cannot read " .. path); return nil end
  local fn, perr = load(src, "=" .. path, "t", { string = string, table = table, math = math })
  if not fn then err("parse: " .. perr); return nil end
  local ok, t = pcall(fn)
  if not ok or type(t) ~= "table" then err("not a valid package"); return nil end
  return t
end

local function quoteString(s)
  -- Long bracket form, with adaptive level so nothing inside conflicts.
  local level = 0
  while s:find("]" .. string.rep("=", level) .. "]", 1, true) do
    level = level + 1
    if level > 12 then break end
  end
  local eq = string.rep("=", level)
  return "[" .. eq .. "[\n" .. s .. "]" .. eq .. "]"
end

local function emitTable(t)
  local out = { "return {\n" }
  if t.format then
    out[#out + 1] = ("  format = %q,\n"):format(t.format)
  end
  out[#out + 1] = "  files = {\n"
  -- deterministic order
  local keys = {}
  for k_ in pairs(t.files or {}) do keys[#keys + 1] = k_ end
  table.sort(keys)
  for _, k_ in ipairs(keys) do
    local v = t.files[k_]
    if v:find("[^%g \n\r\t]") then
      -- non-printable bytes: quote with %q (escapes everything)
      out[#out + 1] = ("    [%q] = %q,\n"):format(k_, v)
    else
      out[#out + 1] = ("    [%q] = %s,\n"):format(k_, quoteString(v))
    end
  end
  out[#out + 1] = "  },\n"
  out[#out + 1] = "}\n"
  return table.concat(out)
end

local function compressPkg(input, output)
  local t = loadPkg(input); if not t then return 1 end
  if t.format and t.format ~= "raw" then
    err("input is already encoded: format=" .. t.format); return 1
  end

  local origSize, encSize = 0, 0
  for path, content in pairs(t.files or {}) do
    origSize = origSize + #content
    local enc = compress.encode(content)
    encSize = encSize + #enc
    t.files[path] = enc
    info(("  %-30s  %5d -> %5d  (%.0f%%)")
      :format(path, #content, #enc, 100 * #enc / math.max(1, #content)))
  end
  t.format = "lzw1"

  local body = emitTable(t)
  fs.writeAll(output, body)
  info(("wrote %s  payload %d -> %d  (%.0f%%)")
    :format(output, origSize, encSize, 100 * encSize / math.max(1, origSize)))
  return 0
end

local function decompressPkg(input, output)
  local t = loadPkg(input); if not t then return 1 end
  if t.format ~= "lzw1" then err("input is not lzw1"); return 1 end
  for path, content in pairs(t.files or {}) do
    local plain = compress.decode(content)
    if not plain then err("decompress failed for " .. path); return 1 end
    t.files[path] = plain
  end
  t.format = nil
  fs.writeAll(output, emitTable(t))
  info("wrote " .. output)
  return 0
end

-- ---- CLI -------------------------------------------------------------------
if not args[1] then
  term.write("usage:\n")
  term.write("  mkpkg <input.pkg> [output.pkg.z]\n")
  term.write("  mkpkg -d <input.pkg.z> [output.pkg]\n")
  return 1
end

if args[1] == "-d" then
  local inp = args[2]; if not inp then err("missing input"); return 1 end
  local out = args[3] or (inp:gsub("%.pkg%.z$", ".pkg"))
  if out == inp then out = inp .. ".out" end
  return decompressPkg(inp, out)
end

local inp = args[1]
local out = args[2] or (inp:gsub("%.pkg$", "") .. ".pkg.z")
return compressPkg(inp, out)
