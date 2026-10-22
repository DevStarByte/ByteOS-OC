--[[
  tools/gendocs.lua - the command reference of the documentation site

    lua tools/gendocs.lua      writes docs/reference/commands.md

  Every command's manual page is the comment at the top of its program
  (see bin/man.lua), so the reference is made from those: a table of all
  commands with their first line, then each page as `man` shows it. The
  docs workflow runs this before building the site; the file it writes is
  not kept in git. Needs Lua 5.3+ and a POSIX shell (for listing files).
]]--

local here = (arg[0]:match("^(.*)/tools/[^/]*$")) or "."
local function q(p) return "'" .. p:gsub("'", "'\\''") .. "'" end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("a"); f:close()
  return d
end

-- The leading comment of a program, as bin/man.lua reads it.
local function header(src)
  src = src:gsub("\r", "")
  local block = src:match("^%-%-%[%[\n?(.-)%]%]")
  if block then
    local indent
    for l in block:gmatch("[^\n]+") do
      local sp = #l:match("^ *")
      if l:match("%S") and (not indent or sp < indent) then indent = sp end
    end
    local out = {}
    for l in (block .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = l:sub((indent or 0) + 1) end
    return (table.concat(out, "\n"):gsub("^\n+", ""):gsub("\n+$", ""))
  end
  local out = {}
  for l in (src .. "\n"):gmatch("([^\n]*)\n") do
    local text = l:match("^%-%- ?(.*)$")
    if not text then break end
    out[#out + 1] = text
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

-- What a page's first lines say the command does:
--   "head [-n N] [file...] - the first N lines"     -> "the first N lines"
--   "cmp [-s] FILE1 FILE2   compare two files ..."  -> "compare two files ..."
-- continued on the next lines until the sentence ends.
local function summary(name, text)
  local lines = {}
  for l in (text .. "\n"):gmatch("([^\n]*)\n") do
    if not l:match("%S") then break end
    lines[#lines + 1] = l
  end
  local desc = lines[1]:match("^%S.- %- (.+)$") or lines[1]:match("^%S.-%s%s%s+(%S.*)$")
  local from = 2
  if not desc then
    -- usage lines first, the description indented below them (seq)
    for i = 2, #lines do
      if lines[i]:match("^%s+%l") then desc, from = lines[i]:match("^%s*(.-)%s*$"), i + 1; break end
    end
    desc = desc or lines[1]
  end
  for i = from, #lines do
    local l = lines[i]
    if desc:match("[.:]%s*$") or not l:match("^%s*%l") or l:match("^%s*" .. name .. "[%s%[]") then break end
    desc = desc .. " " .. l:match("^%s*(.-)%s*$")
  end
  -- the first sentence (an "e.g." does not end one)
  local cut = desc:gsub("e%.g%.", "e\1g\1")
  desc = ((cut:match("^(.-[^.]%.)%s") or cut):gsub("\1", "."))
  return (desc:gsub("%s+$", ""):gsub("[,;:]$", ""):gsub("|", "\\|"))
end

local pages = {}
for _, dir in ipairs({ "bin", "sbin" }) do
  local h = io.popen("ls -1 " .. q(here .. "/" .. dir) .. " 2>/dev/null")
  for f in h:lines() do
    local name = f:match("^(.+)%.lua$")
    -- /sbin/init is PID 1, not something to run
    if name and not (dir == "sbin" and name == "init") then
      local text = header(read(here .. "/" .. dir .. "/" .. f) or "")
      if text then pages[#pages + 1] = { name = name, path = "/" .. dir .. "/" .. f, text = text } end
    end
  end
  h:close()
end
table.sort(pages, function(a, b) return a.name < b.name end)

local out = {
  "# Commands",
  "",
  "Every command of the base system with its manual page, exactly as `man <command>` shows",
  "it inside ByteOS. Shell built-ins (`cd`, `alias`, `trap`, ...) are described in",
  "[Scripts](../using/scripting.md) and `man byteshell`; commands from packages are on the",
  "[package list](../packages/list.md).",
  "",
  "!!! note",
  "    This page is made from the programs themselves (`tools/gendocs.lua`), so it always",
  "    matches the newest ByteOS.",
  "",
  "| Command | What it does |",
  "|---|---|",
}
for _, p in ipairs(pages) do
  out[#out + 1] = ("| [`%s`](#%s) | %s |"):format(p.name, p.name, summary(p.name, p.text))
end
out[#out + 1] = ""
for _, p in ipairs(pages) do
  out[#out + 1] = ("## %s { #%s }"):format(p.name, p.name)
  out[#out + 1] = ""
  out[#out + 1] = "`" .. p.path .. "`"
  out[#out + 1] = ""
  out[#out + 1] = "```text"
  out[#out + 1] = p.text
  out[#out + 1] = "```"
  out[#out + 1] = ""
end

local path = here .. "/docs/reference/commands.md"
os.execute("mkdir -p " .. q(here .. "/docs/reference"))
local f = assert(io.open(path, "wb"))
f:write(table.concat(out, "\n"))
f:close()
print(("%d commands written to docs/reference/commands.md"):format(#pages))
