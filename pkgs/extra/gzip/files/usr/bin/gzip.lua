--[[
  gzip - pack files into .gz, or unpack them (gunzip, zcat)

    gzip FILE...       FILE becomes FILE.gz
    gzip -d FILE.gz... unpack (the same as gunzip)
    -c                 write to the output instead (a pipe or > file),
                       the files stay as they are
    -k                 keep the original files
    -f                 overwrite existing files; write packed data to the
                       screen
    -1 ... -9          faster ... smaller (default -6)
    -v                 say how much each file shrank

  Without files (or with -) it packs its input into its output:
    tar -cf - notes | gzip > notes.tar.gz      wget -O - URL | gunzip

  .gz files from a PC open here and the other way round; ByteOS packs with
  the fixed Huffman codes, so its files are a little bigger than a PC's.
  Damaged data (a wrong CRC) is reported and nothing is replaced.
]]--
local deflate = require("deflate")
package.loaded.deflate = nil -- gone from memory once gzip ends
local args = arg or {}

local decompress, toStdout, keep, force, verbose, level = false, false, false, false, false, 6
local files = {}
for _, a in ipairs(args) do
  if a:match("^%-[%a%d]+$") then
    for c in a:sub(2):gmatch(".") do
      if c == "d" then decompress = true
      elseif c == "c" then toStdout = true
      elseif c == "k" then keep = true
      elseif c == "f" then force = true
      elseif c == "v" then verbose = true
      elseif c:match("%d") and c ~= "0" then level = tonumber(c)
      else term.write("gzip: unknown option -" .. c .. "\n"); return 2 end
    end
  else
    files[#files + 1] = a
  end
end
if #files == 0 then files[1] = "-" end

local function breathe() k.event.pull(0) end
local piped = stdio and stdio.output ~= nil
local rc = 0
-- messages go to the screen (the error output), never into the data
local function fail(msg) shell.err("gzip", msg); rc = 1 end

-- Pieces of a file (a reader for deflate.gunzip), or of the whole input.
local function source(name)
  if name == "-" then
    local all = stdin.read("a") or ""
    return function() local c = all; all = nil; return c end
  end
  local f, e = fs.open(shell.normalize(name), "r")
  if not f then return nil, e end
  return function()
    local c = f and f:read(8192)
    if not c and f then f:close(); f = nil end
    return c
  end
end

-- Where the result goes: the output, or a new file (written once all
-- went well: an error leaves nothing half-written behind).
local function target(path)
  if not path then
    if not piped and not force and not decompress then
      return nil, "packed data is not written to the screen (use > or a pipe, or -f)"
    end
    -- into a pipe or file the bytes go as they are (term would treat them as text)
    local write = piped and function(s) stdio.output[#stdio.output + 1] = s end or term.write
    return { write = write, close = function() return true end }
  end
  if fs.exists(path) and not force then return nil, path .. " already exists (-f overwrites it)" end
  local tmp = path .. ".part"
  local f, e = fs.open(tmp, "w")
  if not f then return nil, e end
  return {
    write = function(s) f:write(s) end,
    close = function(ok)
      f:close()
      if not ok then fs.remove(tmp); return false end
      if fs.exists(path) then fs.remove(path) end
      local done, err = fs.rename(tmp, path)
      if not done then fs.remove(tmp); return nil, err end
      return true
    end,
  }
end

for _, name in ipairs(files) do
  local path = name ~= "-" and shell.normalize(name) or nil
  if path and fs.isDirectory(path) then
    fail(name .. " is a directory, skipped")
  elseif path and not fs.exists(path) then
    fail(name .. ": no such file")
  else
    local outPath
    if path and not toStdout then
      if decompress then
        if path:match("%.gz$") then outPath = path:sub(1, -4)
        elseif path:match("%.tgz$") then outPath = path:sub(1, -5) .. ".tar"
        else fail(name .. ": unknown suffix (not .gz or .tgz), skipped") end
      else
        if path:match("%.gz$") or path:match("%.tgz$") then fail(name .. " already has the .gz suffix, skipped")
        else outPath = path .. ".gz" end
      end
    end
    if outPath or toStdout or not path then
      local src, serr = source(name)
      local out, oerr
      if src then out, oerr = target(outPath) end
      if not src then fail(name .. ": " .. tostring(serr))
      elseif not out then fail(tostring(oerr))
      else
        local inSize, outSize = 0, 0
        local function write(s) outSize = outSize + #s; out.write(s) end
        local ok, err
        if decompress then
          ok, err = deflate.gunzip(function()
            local c = src()
            if c then inSize = inSize + #c end
            return c
          end, write, breathe)
        else
          local g = deflate.gzipStream(write, {
            level = level, breathe = breathe,
            name = path and path:match("[^/]+$"),
            mtime = path and fs.lastModified and fs.lastModified(path) or 0,
          })
          ok, err = pcall(function()
            for c in src do inSize = inSize + #c; g.write(c) end
            g.finish()
          end)
        end
        local closed, cerr = out.close(ok)
        if not ok then fail(name .. ": " .. tostring(err))
        elseif not closed then fail(name .. ": " .. tostring(cerr))
        else
          if path and not toStdout and not keep then fs.remove(path) end
          if verbose then
            local before, after = decompress and outSize or inSize, decompress and inSize or outSize
            local saved = before > 0 and (1 - after / before) * 100 or 0
            local screen = outPath and term or rawget(_G, "term") or term
            screen.write(("%s:\t%5.1f%%%s\n"):format(name, saved, outPath and (" -- replaced with " .. outPath:match("[^/]+$")) or ""))
          end
        end
      end
    end
  end
end
return rc
