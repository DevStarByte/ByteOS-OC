--[[
  man <name>    the manual page of a command or topic
  man -k word   which pages mention word in their first line

  A command's page is the comment at the top of its program, so it is
  always the same version as the program (this applies to commands from
  packages, too). Topics without a command live in /usr/share/man/<name>.txt:
  byteshell, byteos, pacman.conf, PKGBUILD, systemd.service, man.
  Shell built-ins (cd, alias, jobs, ...) are described in `man byteshell`.

  On the screen the page opens in less (q quits); into a pipe or file it
  is just printed.
]]--
local args = arg or {}
local MANDIR = "/usr/share/man"

-- The leading comment of a Lua program: a --[[ ... ]] block or the
-- consecutive "--" lines at the top.
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

-- The page text for name, or nil.
local function page(name)
  local topic = fs.readAll(MANDIR .. "/" .. name .. ".txt")
  if topic then return topic end
  if shell.builtins[name] then
    local intro = ("%s is a ByteShell built-in command; built-ins are described here.\n\n"):format(name)
    return intro .. (fs.readAll(MANDIR .. "/byteshell.txt") or "")
  end
  local path = shell.resolveBin(name)
  if path then
    local src = fs.readAll(path)
    local text = src and header(src)
    if text then return ("%s(1)  %s\n\n%s\n"):format(name, path, text) end
  end
end

-- man -k: the first line of every page and command
local function apropos(word)
  word = word:lower()
  local found = {}
  local function consider(name, text)
    local first = (text or ""):gsub("^%s+", ""):match("^[^\n]*") or ""
    if (name .. " " .. first):lower():find(word, 1, true) then found[#found + 1] = { name, first } end
  end
  for _, f in ipairs(fs.list(MANDIR) or {}) do
    local name = f:match("^(.+)%.txt$")
    if name then consider(name, fs.readAll(MANDIR .. "/" .. f)) end
  end
  local seen = {}
  for dir in (_G.PATH or "/bin"):gmatch("[^:]+") do
    for _, f in ipairs(fs.list(dir) or {}) do
      local name = f:match("^(.+)%.lua$")
      if name and not seen[name] then
        seen[name] = true
        consider(name, header(fs.readAll(dir .. "/" .. f) or "") or "")
      end
    end
  end
  table.sort(found, function(a, b) return a[1] < b[1] end)
  for _, f in ipairs(found) do term.write(("%-14s %s\n"):format(f[1], f[2])) end
  if #found == 0 then term.write(word .. ": nothing appropriate.\n"); return 1 end
  return 0
end

if args[1] == "-k" then
  if not args[2] then term.write("usage: man -k word\n"); return 1 end
  return apropos(args[2])
end
if not args[1] then term.write("What manual page do you want?\nFor example, try 'man man'.\n"); return 1 end

local text = page(args[1])
if not text then term.write("No manual entry for " .. args[1] .. "\n"); return 16 end
if stdio and stdio.output then term.write(text); return 0 end
-- through a file, so that less still reads its keys (and /search) from the keyboard
local tmp = ("/tmp/man-%s-%s.txt"):format(k.user(), args[1]:gsub("[^%w%.%-_]", "_"))
fs.writeAll(tmp, text)
local rc = shell.run("less " .. tmp)
fs.remove(tmp)
return rc
