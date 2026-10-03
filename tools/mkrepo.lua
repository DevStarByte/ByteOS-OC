--[[
  tools/mkrepo.lua - build every package and the repo databases on a PC

    lua tools/mkrepo.lua <packages-checkout>

  Reads the package sources in <checkout>/pkgs/<repo>/<name>/ (layout: see
  lib/bpk.lua) and writes, for every repo:
    <checkout>/<repo>/<name>-<version>.bpk
    <checkout>/<repo>/<repo>.db
  .bpk files in <checkout>/<repo>/ without a source are deleted. Nothing is
  written for a repo in which any package fails to build.

  Needs Lua 5.3 or newer and a POSIX shell (for listing directories).
]]--

local here = (arg[0]:match("^(.*)/tools/[^/]*$")) or "."
package.path = here .. "/lib/?.lua;" .. package.path
local bpk = require("bpk")

local root = arg[1]
if not root then
  io.stderr:write("usage: lua tools/mkrepo.lua <packages-checkout>\n")
  os.exit(2)
end

local function q(p) return "'" .. p:gsub("'", "'\\''") .. "'" end

local fsx = {}
function fsx.readAll(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local d = f:read("a"); f:close()
  return d
end
function fsx.isDirectory(p) return os.execute("test -d " .. q(p)) == true end
function fsx.list(d)
  local out = {}
  local h = io.popen("ls -1Ap " .. q(d) .. " 2>/dev/null")
  for l in h:lines() do out[#out + 1] = l end
  h:close()
  table.sort(out)
  return out
end

local failed = false
for _, repoEntry in ipairs(fsx.list(root .. "/pkgs")) do
  local repo = repoEntry:match("^(.-)/$")
  if repo then
    local outDir = root .. "/" .. repo
    os.execute("mkdir -p " .. q(outDir))
    local db, keep, ok = {}, {}, true
    for _, pkgEntry in ipairs(fsx.list(root .. "/pkgs/" .. repo)) do
      local name = pkgEntry:match("^(.-)/$")
      if name then
        local entries, info = bpk.build(root .. "/pkgs/" .. repo .. "/" .. name, fsx)
        if not entries then
          io.stderr:write(("error: %s/%s: %s\n"):format(repo, name, info))
          ok = false
        elseif info.name ~= name then
          io.stderr:write(("error: %s/%s: PKGBUILD name is '%s'\n"):format(repo, name, info.name))
          ok = false
        else
          local parts = {}
          bpk.write({ write = function(_, s) parts[#parts + 1] = s end }, entries)
          local blob = table.concat(parts)
          info.filename = bpk.filename(info)
          info.csize = #blob
          info.crc32 = bpk.hex(bpk.crc32(blob))
          db[#db + 1] = info
          keep[info.filename] = blob
        end
      end
    end
    if ok then
      table.sort(db, function(a, b) return a.name < b.name end)
      for file, blob in pairs(keep) do
        if fsx.readAll(outDir .. "/" .. file) ~= blob then
          local f = assert(io.open(outDir .. "/" .. file, "wb")); f:write(blob); f:close()
        end
      end
      for _, f in ipairs(fsx.list(outDir)) do
        if f:match("%.bpk$") and not keep[f] then os.remove(outDir .. "/" .. f) end
      end
      local f = assert(io.open(outDir .. "/" .. repo .. ".db", "wb"))
      f:write(bpk.formatDb(db)); f:close()
      for _, info in ipairs(db) do
        print(("%-8s %-28s %6d -> %6d bytes"):format(repo, info.filename, info.isize, info.csize))
      end
    else
      failed = true
      io.stderr:write("error: repo '" .. repo .. "' was not written\n")
    end
  end
end
os.exit(failed and 1 or 0)
