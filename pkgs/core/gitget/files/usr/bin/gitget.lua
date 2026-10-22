--[[
  gitget - download a GitHub repository, or one folder or file of it

    gitget USER/REPO[@BRANCH] [PATH] [-o DIR] [-n] [-f]

    gitget DevStarByte/ByteOS-OC                 the whole repository
    gitget DevStarByte/ByteOS-OC bin -o /tmp/b   only its bin folder
    gitget someone/tools@dev util/x.lua          one file, from branch dev

  The files go into DIR (default: a new folder named after the repository
  or the folder, or here for a single file). Without @BRANCH it takes the
  repository's default branch.

    -n   only list what would be downloaded
    -f   go on although the disk looks too small, overwrite files
    -s KiB  skip files bigger than this (default 256)

  GitHub answers 60 questions an hour without signing in; gitget asks two
  per download, then fetches the files themselves (which do not count).
]]--
local args = arg or {}
local internet = require("internet")
local okJson, json = pcall(require, "json")

local function err(msg) term.write("gitget: " .. msg .. "\n") end

local spec, sub, outDir, dry, force, limit = nil, nil, nil, false, false, 256 * 1024
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-o" then i = i + 1; outDir = args[i]
  elseif a == "-n" then dry = true
  elseif a == "-f" then force = true
  elseif a == "-s" then i = i + 1; limit = tonumber(args[i]) and tonumber(args[i]) * 1024
    if not limit then err("-s needs a size in KiB"); return 2 end
  elseif a:sub(1, 1) == "-" then err("unknown option " .. a); return 2
  elseif not spec then spec = a
  elseif not sub then sub = a
  else err("too many arguments"); return 2 end
  i = i + 1
end
local name = (spec or ""):gsub("^https?://github%.com/", ""):gsub("/+$", "")
local user, repo, branch = name:match("^([%w%-_%.]+)/([%w%-_%.]+)@([%w%-_%./]+)$")
if not user then
  user, repo = name:match("^([%w%-_%.]+)/([%w%-_%.]+)$")
  branch = ""
end
if not user then
  term.write("usage: gitget USER/REPO[@BRANCH] [PATH] [-o DIR] [-n] [-f] [-s KiB]\n"); return 2
end
repo = repo:gsub("%.git$", "")
sub = sub and sub:gsub("^/+", ""):gsub("/+$", "") or ""
if not okJson then err("needs the lua-json package: sudo pacman -S lua-json"); return 1 end
if not internet.available() then err("no internet card"); return 1 end

local API = "https://api.github.com/repos/" .. user .. "/" .. repo

-- GitHub's answer as a table, or nil after saying what went wrong
local function api(url, what)
  local text, why, status = internet.fetch(url, { Accept = "application/vnd.github+json" })
  if not text then
    if status == 404 then err(what .. " not found (or it is private)")
    elseif status == 403 or status == 429 then
      err("GitHub refused: too many questions (60 an hour without signing in); try again later")
    else err(tostring(why)) end
    return nil
  end
  local data, perr = json.decode(text)
  if type(data) ~= "table" then err("GitHub sent something unexpected: " .. tostring(perr)); return nil end
  return data
end

if branch == "" then
  local info = api(API, "repository " .. user .. "/" .. repo)
  if not info then return 1 end
  branch = info.default_branch or "master"
end
local tree = api(API .. "/git/trees/" .. branch .. "?recursive=1", "branch " .. branch .. " of " .. user .. "/" .. repo)
if not tree then return 1 end
if type(tree.tree) ~= "table" then err("GitHub sent no file list"); return 1 end
if tree.truncated then err("the repository is too big for one list; some files are missing (name a folder)") end

-- the files to fetch: { path in the repository, path below the target, size }
local files, total, skipped, isFile = {}, 0, {}, false
for _, e in ipairs(tree.tree) do
  if e.type == "blob" and type(e.path) == "string" then
    local rel
    if sub == "" then rel = e.path
    elseif e.path == sub then rel = e.path:match("[^/]*$"); isFile = true
    elseif e.path:sub(1, #sub + 1) == sub .. "/" then rel = e.path:sub(#sub + 2) end
    if rel then
      local size = tonumber(e.size) or 0
      if size > limit then skipped[#skipped + 1] = ("%s (%d KiB)"):format(e.path, size // 1024)
      else
        files[#files + 1] = { path = e.path, rel = rel, size = size }
        total = total + size
      end
    end
  end
end
if #files == 0 and #skipped == 0 then
  err(sub ~= "" and ("nothing called " .. sub .. " in " .. user .. "/" .. repo .. "@" .. branch) or "the repository is empty")
  return 1
end
table.sort(files, function(a, b) return a.path < b.path end)

local dir = shell.normalize(outDir or (isFile and ".") or (sub ~= "" and sub:match("[^/]*$")) or repo)
local function kib(n) return n < 1024 and (n .. " B") or ("%.1f KiB"):format(n / 1024) end

if dry then
  for _, f in ipairs(files) do term.write(("%9s  %s\n"):format(kib(f.size), f.path)) end
  for _, s in ipairs(skipped) do term.write("  skipped: " .. s .. "\n") end
  term.write(("%d files, %s -> %s\n"):format(#files, kib(total), dir))
  return 0
end

-- is there room on the disk?
local proxy = fs.resolve(dir)
if proxy and proxy.spaceTotal and proxy.spaceUsed then
  local okT, t = pcall(proxy.spaceTotal)
  local okU, u = pcall(proxy.spaceUsed)
  if okT and okU and type(t) == "number" and type(u) == "number" and total > t - u then
    err(("%s to download, but only %s free on that disk"):format(kib(total), kib(math.max(0, t - u))))
    if not force then term.write("  (-f tries anyway, -n lists the files, PATH picks a folder)\n"); return 1 end
  end
end

local function mkdirs(p)
  if fs.isDirectory(p) then return true end
  local parent = p:match("^(.*)/[^/]+$")
  if parent and parent ~= "" then mkdirs(parent) end
  return fs.makeDirectory(p)
end

local function urlPath(p)
  return (p:gsub("[^%w%-_%.~/]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local raw = "https://raw.githubusercontent.com/" .. user .. "/" .. repo .. "/" .. branch .. "/"
local failed = 0
for n, f in ipairs(files) do
  local dest = dir .. "/" .. f.rel
  term.write(("(%d/%d) %s  %s\n"):format(n, #files, f.path, kib(f.size)))
  if fs.exists(dest) and not force then
    term.write("  exists, kept (-f overwrites)\n")
  else
    mkdirs(dest:match("^(.*)/[^/]+$") or "/")
    local text, why = internet.fetch(raw .. urlPath(f.path))
    local ok, werr
    if text then ok, werr = fs.writeAll(dest, text) end
    if not text or not ok then
      term.write("  failed: " .. tostring(why or werr) .. "\n")
      failed = failed + 1
    end
  end
end
for _, s in ipairs(skipped) do term.write("skipped, too big: " .. s .. " (-s raises the limit)\n") end
term.write(("%d of %d files in %s\n"):format(#files - failed, #files, dir))
return failed > 0 and 1 or 0
