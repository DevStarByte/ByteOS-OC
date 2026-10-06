--[[
  /lib/shell.lua - ByteShell, an Arch-flavoured POSIX-ish shell
]]--

local k    = _G.kernel
local fs   = k.fs
local term = require("term")
local T    = term.theme

-- Where built-ins print. Normally the terminal; while a built-in's output
-- goes to a pipe or a file (alias > aliases.txt) it is a capturing stand-in.
local out = term

local shell = {}
shell.history = {}   -- this user's command history, oldest first

-- Each terminal (the screen, every window of a window manager) is a
-- session of its own with these:
--   shell.status       exit status of the last command ($status, $?)
--   shell.jobs         background jobs: { id, pid, cmd }
--   shell.interrupted  Ctrl+C stopped the last command
local SESSION = { status = true, jobs = true, interrupted = true }
local sessions = setmetatable({}, { __mode = "k" })
local screenSession = {}
local function session()
  local t = k.process.tty()
  if not t then return screenSession end
  local s = sessions[t]
  if not s then s = {}; sessions[t] = s end
  return s
end
local function fresh(key) if key == "jobs" then return {} elseif key == "status" then return 0 end return false end
setmetatable(shell, {
  __index = function(_, key)
    if not SESSION[key] then return nil end
    local s = session()
    if s[key] == nil then s[key] = fresh(key) end
    return s[key]
  end,
  __newindex = function(t, key, v)
    if SESSION[key] then session()[key] = v else rawset(t, key, v) end
  end,
})

-- Script parameters ($0 $1 ...) and a script's default input/output belong
-- to whoever runs the script: the foreground or one background process.
local contexts = {}
local function ctx()
  local pid = k.process.current() or 0
  local c = contexts[pid]
  if not c then
    c = { params = { [0] = "byteshell" }, ambient = {} }
    contexts[pid] = c
  end
  return c
end

-- Send this process's error messages to fn(text) instead of the screen
-- (services log them). shell.errorSink() returns the current one.
function shell.setErrorSink(fn) ctx().errors = fn end
function shell.errorSink() return ctx().errors end

-- Print an error message: "<prog>: " in red, the message in the default colour.
function shell.err(prog, msg)
  local sink = shell.errorSink and shell.errorSink()
  if sink then return sink(prog .. ": " .. tostring(msg) .. "\n") end
  term.cwrite(T.err, prog .. ": ")
  term.cwrite(T.fg, tostring(msg) .. "\n")
end

-- ---- Path helpers --------------------------------------------------------
function shell.normalize(path)
  if path:sub(1,1) ~= "/" then path = (_G.PWD or "/") .. "/" .. path end
  local parts = {}
  for seg in path:gmatch("[^/]+") do
    if seg == ".." then table.remove(parts) elseif seg ~= "." then table.insert(parts, seg) end
  end
  return "/" .. table.concat(parts, "/")
end

-- Looking a command up costs two disk calls per $PATH directory, and the
-- highlighting does it at every key press, so the answers (also "not
-- found") are kept until something on the disks changes.
local binCache, binGen = {}, nil

function shell.resolveBin(name)
  if name:find("/") then return shell.normalize(name) end
  local path = _G.PATH or "/bin:/usr/bin:/sbin"
  local gen = fs.generation()
  if gen ~= binGen then binCache, binGen = {}, gen end
  local key = path .. "\0" .. name
  local hit = binCache[key]
  if hit ~= nil then return hit or nil end
  local found = false
  for dir in path:gmatch("[^:]+") do
    local p = dir .. "/" .. name .. ".lua"
    if fs.exists(p) and not fs.isDirectory(p) then found = p; break end
    p = dir .. "/" .. name
    if fs.exists(p) and not fs.isDirectory(p) then found = p; break end -- not "/bin/.."
  end
  binCache[key] = found
  return found or nil
end

-- The text of a program to run. Small ones are kept (up to PROGRAM_CACHE
-- bytes in all, while memory is not short) until something on the disks
-- changes, so a loop does not read the same file from disk every round.
-- Kept per user: a file one user may read is not handed to another.
local PROGRAM_CACHE, PROGRAM_MAX = 16384, 6144
local progCache, progGen, progBytes = {}, nil, 0
local function readProgram(path)
  local gen = fs.generation()
  if gen ~= progGen then progCache, progGen, progBytes = {}, gen, 0 end
  local key = k.user() .. ":" .. path
  local src = progCache[key]
  if src then return src end
  local err
  src, err = fs.readAll(path)
  if src and #src <= PROGRAM_MAX and computer.freeMemory() > 65536 then
    if progBytes + #src > PROGRAM_CACHE then progCache, progBytes = {}, 0 end
    progCache[key], progBytes = src, progBytes + #src
  end
  return src, err
end

-- ---- Variables -----------------------------------------------------------
-- Shell variables live in _G next to the Lua globals, so only UPPERCASE
-- names starting with a letter are allowed: `export term=x` must not
-- replace the term library, nor `_G=x` the globals table.
function shell.validName(name)
  return type(name) == "string" and name:match("^%u[%u%d_]*$") ~= nil
end

function shell.getVar(name)
  local v = _G[name]
  if shell.validName(name) and (type(v) == "string" or type(v) == "number") then
    return tostring(v)
  end
  return ""
end

-- The index of the ) that closes the ( at i, skipping quoted text and
-- nested parentheses; the end of s if it is never closed.
local function closeParen(s, i)
  local depth, q, n = 0, nil, #s
  while i <= n do
    local c = s:sub(i, i)
    if q then
      if c == q then q = nil elseif c == "\\" and q == '"' then i = i + 1 end
    elseif c == "'" or c == '"' then q = c
    elseif c == "\\" then i = i + 1
    elseif c == "(" then depth = depth + 1
    elseif c == ")" then
      depth = depth - 1
      if depth == 0 then return i end
    end
    i = i + 1
  end
  return n
end

-- $(cmd): run cmd and return what it printed, without trailing newlines.
-- `exit` inside only ends the substitution.
function shell.capture(cmd)
  local buf = {}
  local ok, err = pcall(shell.withIO, { output = buf }, shell.execute, cmd)
  if not ok and err ~= "__exit__" then error(err, 0) end
  return (table.concat(buf):gsub("\n+$", ""))
end

-- ---- Tokeniser -----------------------------------------------------------
-- Splits a line into words like a POSIX shell:
--   'single quotes'  everything inside is literal
--   "double quotes"  keep spaces, still expand $VAR and $(cmd)
--   \c               the next character literally (outside single quotes)
--   $NAME ${NAME}    the variable's value
--   $1..$9 $0 $# $@  script arguments ($@ unquoted gives one word each)
--   $(cmd)           what cmd prints; unquoted, one word per line (as fish)
--   ~ ~/...          $HOME at the start of a word
-- Quotes may appear mid-word: ll='ls -l' is one word, "ll=ls -l".
-- Returns the words and, for each, whether it holds an unquoted wildcard
-- (* ? [) to be expanded against the filesystem. With noSubst, $(cmd) is
-- kept as text instead of being run (for highlighting while typing).
function shell.tokenize(line, noSubst)
  local args, globs, word, inWord, glob = {}, {}, {}, false, false
  local i, n = 1, #line
  local params = ctx().params
  local function push(s) word[#word + 1] = s; inWord = true end
  local function finish()
    if inWord then args[#args + 1] = table.concat(word); globs[#args] = glob end
    word, inWord, glob = {}, false, false
  end
  local function variable(j)
    local c = line:sub(j, j)
    if c == "?" then return tostring(shell.status), j + 1 end
    if c == "#" then return tostring(#params), j + 1 end
    if c == "@" or c == "*" then return table.concat(params, " "), j + 1 end
    if c:match("%d") then return params[tonumber(c)] or "", j + 1 end
    local name, nxt = line:match("^{([%w_]+)}()", j)
    if not name then name, nxt = line:match("^([%w_]+)()", j) end
    if not name then return "$", j end
    if name == "status" then return tostring(shell.status), nxt end -- fish's $status
    return shell.getVar(name), nxt
  end
  -- $( at j: the command's output and the index after the closing )
  local function subst(j)
    local e = closeParen(line, j + 1)
    if noSubst then return line:sub(j, e), e + 1 end
    return shell.capture(line:sub(j + 2, e - 1)), e + 1
  end
  while i <= n do
    local c = line:sub(i, i)
    if c == " " or c == "\t" then
      finish(); i = i + 1
    elseif c == "'" then
      local j = line:find("'", i + 1, true) or n + 1
      push(line:sub(i + 1, j - 1)); i = j + 1
    elseif c == '"' then
      i = i + 1
      push("")
      while i <= n and line:sub(i, i) ~= '"' do
        local d = line:sub(i, i)
        if d == "\\" and line:sub(i + 1, i + 1):match('["\\$]') then
          push(line:sub(i + 1, i + 1)); i = i + 2
        elseif d == "$" and line:sub(i + 1, i + 1) == "(" then
          local v; v, i = subst(i); push(v)
        elseif d == "$" then
          local v; v, i = variable(i + 1); push(v)
        else
          push(d); i = i + 1
        end
      end
      i = i + 1
    elseif c == "\\" then
      push(line:sub(i + 1, i + 1)); i = i + 2
    elseif c == "$" and (line:sub(i + 1, i + 1) == "@" or line:sub(i + 1, i + 1) == "*") then
      for idx, a in ipairs(params) do
        if idx > 1 then finish() end
        push(a)
      end
      i = i + 2
    elseif c == "$" and line:sub(i + 1, i + 1) == "(" then
      local v; v, i = subst(i)
      if noSubst then push(v)
      elseif v ~= "" then
        local first = true
        for l in (v .. "\n"):gmatch("([^\n]*)\n") do
          if not first then finish() end
          push(l); first = false
        end
      end
    elseif c == "$" then
      -- an empty unquoted expansion adds no word, as in sh ("$X" would)
      local v; v, i = variable(i + 1)
      if v ~= "" then push(v) end
    elseif c == "~" and not inWord and (i == n or line:sub(i + 1, i + 1):match("[/%s]")) then
      push(_G.HOME or "/"); i = i + 1
    else
      if c == "*" or c == "?" or c == "[" then glob = true end
      push(c); i = i + 1
    end
  end
  finish()
  return args, globs
end
local tokenize = shell.tokenize

-- ---- Aliases -------------------------------------------------------------
shell.aliases = {}

-- Replace an alias in the first word, repeatedly, but never the same alias
-- twice (so `alias ls='ls -1'` works and loops cannot happen).
function shell.expandAliases(line)
  local used = {}
  while true do
    local lead, first, rest = line:match("^(%s*)([^%s'\"\\$]+)(.*)$")
    if not first or (rest ~= "" and not rest:match("^%s")) then return line end
    local value = shell.aliases[first]
    if not value or used[first] then return line end
    used[first] = true
    line = lead .. value .. rest
  end
end

-- Built-ins handled directly in the shell process
shell.builtins = {}

-- cd [dir]   cd - (back to the previous directory)
function shell.builtins.cd(args)
  local target = args[1] or _G.HOME or "/"
  if target == "-" then
    target = _G.OLDPWD
    if not target then shell.err("cd", "no previous directory"); return 1 end
    out.write(target .. "\n")
  end
  local p = shell.normalize(target)
  if not fs.isDirectory(p) then
    shell.err("cd", "not a directory: " .. target)
    return 1
  end
  _G.OLDPWD, _G.PWD = _G.PWD, p
  return 0
end

-- exit [n]: leave the shell, or end a script with status n
function shell.builtins.exit(args)
  shell.exitCode = tonumber(args and args[1]) or shell.status
  error("__exit__", 0)
end

-- Back to the login prompt, even from a nested shell such as StarShell.
function shell.builtins.logout() error("__logout__", 0) end

-- Set by login and su from the kernel's idea of who you are; changing them
-- would only make the prompt lie.
local READONLY = { USER = true, HOME = true, LOGNAME = true }

-- NAME=value; refuses names that are not shell variables (see validName).
local function assign(prog, name, value)
  if not shell.validName(name) then
    shell.err(prog, "'" .. name .. "': not a valid variable name (use UPPERCASE)")
    return 1
  end
  if READONLY[name] then
    shell.err(prog, name .. ": read-only variable")
    return 1
  end
  _G[name] = value
  return 0
end

function shell.builtins.export(args)
  local rc = 0
  for _, a in ipairs(args) do
    local k_, v = a:match("^([^=]+)=(.*)$")
    if k_ and assign("export", k_, v) ~= 0 then rc = 1 end
  end
  return rc
end

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

-- alias              list all aliases
-- alias name         show one
-- alias name=value   define one (quote values with spaces: alias ll='ls -l')
function shell.builtins.alias(args)
  if #args == 0 then
    local names = {}
    for n in pairs(shell.aliases) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do out.write("alias " .. n .. "=" .. quote(shell.aliases[n]) .. "\n") end
    return 0
  end
  local rc = 0
  for _, a in ipairs(args) do
    local name, value = a:match("^([^=]+)=(.*)$")
    if name then
      if name:find("[%s'\"\\$/]") then
        shell.err("alias", "'" .. name .. "': invalid alias name"); rc = 1
      else
        shell.aliases[name] = value
      end
    elseif shell.aliases[a] then
      out.write("alias " .. a .. "=" .. quote(shell.aliases[a]) .. "\n")
    else
      shell.err("alias", a .. ": not found"); rc = 1
    end
  end
  return rc
end

-- unalias name...   unalias -a (remove all)
function shell.builtins.unalias(args)
  if #args == 0 then shell.err("unalias", "usage: unalias [-a] name..."); return 1 end
  local rc = 0
  for _, a in ipairs(args) do
    if a == "-a" then shell.aliases = {}
    elseif shell.aliases[a] then shell.aliases[a] = nil
    else shell.err("unalias", a .. ": not found"); rc = 1 end
  end
  return rc
end

-- source file  /  . file: run every line of a file in this shell.
function shell.source(path)
  local src = fs.readAll(path)
  if not src then return nil, "cannot read " .. path end
  return shell.execute(src)
end

function shell.builtins.source(args)
  if not args[1] then shell.err("source", "usage: source <file>"); return 1 end
  local rc, e = shell.source(shell.normalize(args[1]))
  if not rc then shell.err("source", e); return 1 end
  return rc
end
shell.builtins["."] = shell.builtins.source

-- set                    list variables
-- set NAME value...      set one, as in fish (-x/-g are accepted: every
--                        variable is global and exported here)
-- set -e NAME            erase one
function shell.builtins.set(args)
  if args and #args > 0 then
    local erase = false
    while args[1] and args[1]:sub(1, 1) == "-" do
      local f = table.remove(args, 1)
      if f == "-e" or f == "--erase" then erase = true
      elseif not (f == "-x" or f == "-g" or f == "-U" or f == "--export" or f == "--global") then
        shell.err("set", "unknown option " .. f); return 1
      end
    end
    local name = table.remove(args, 1)
    if not name then shell.err("set", "usage: set [-e] NAME [value...]"); return 1 end
    if erase then
      if not shell.validName(name) then shell.err("set", "'" .. name .. "': not a variable"); return 1 end
      if READONLY[name] then shell.err("set", name .. ": read-only variable"); return 1 end
      _G[name] = nil
      return 0
    end
    return assign("set", name, table.concat(args, " "))
  end
  local names = {}
  for name, v in pairs(_G) do
    if shell.validName(name) and (type(v) == "string" or type(v) == "number") then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    out.cwrite(T.blue, name); out.cwrite(T.muted, "=")
    out.cwrite(T.fg, tostring(_G[name]) .. "\n")
  end
  return 0
end

-- ---- History -------------------------------------------------------------
-- Every command goes to ~/.byteshell_history. Like fish, a command that
-- starts with a space is not remembered, and a repeated command moves to
-- the end instead of being stored twice.
shell.HISTMAX = 500

local function histFile() return (_G.HOME or "/") .. "/.byteshell_history" end

-- Load this user's history, dropping duplicates (the newest copy wins).
function shell.loadHistory()
  local lines, seen, keep = {}, {}, {}
  for l in (fs.exists(histFile()) and fs.readAll(histFile()) or ""):gmatch("[^\r\n]+") do
    lines[#lines + 1] = l
  end
  for i = #lines, 1, -1 do
    if not seen[lines[i]] and #keep < shell.HISTMAX then
      seen[lines[i]] = true
      keep[#keep + 1] = lines[i]
    end
  end
  shell.history = {}
  for i = #keep, 1, -1 do shell.history[#shell.history + 1] = keep[i] end
  if #shell.history ~= #lines then -- write the tidied file back
    pcall(fs.writeAll, histFile(), table.concat(shell.history, "\n") .. (#keep > 0 and "\n" or ""))
  end
end

function shell.addHistory(line)
  if line:match("^%s") or line:match("^%s*$") then return end
  line = line:gsub("%s+$", "")
  local h = shell.history
  for i = #h, 1, -1 do
    if h[i] == line then table.remove(h, i) end
  end
  h[#h + 1] = line
  while #h > shell.HISTMAX do table.remove(h, 1) end
  local f = fs.open(histFile(), "a")
  if f then f:write(line .. "\n"); f:close() end
end

-- history                newest first
-- history search <text>  only lines containing text
-- history clear          forget everything
function shell.builtins.history(args)
  local sub = args[1]
  if sub == "clear" then
    shell.history = {}
    pcall(fs.writeAll, histFile(), "")
    return 0
  end
  if sub and sub ~= "search" then
    shell.err("history", "usage: history [search <text> | clear]"); return 1
  end
  local text = sub == "search" and table.concat(args, " ", 2) or nil
  for i = #shell.history, 1, -1 do
    local h = shell.history[i]
    if not text or h:find(text, 1, true) then out.write(h .. "\n") end
  end
  return 0
end

-- ---- Running commands ----------------------------------------------------
-- Splits a line at ; && || & outside quotes. A # at the start of a word
-- starts a comment. Returns the parts and the operator after each part.
function shell.split(line)
  local parts, ops, cur = {}, {}, {}
  local i, n, q = 1, #line, nil
  local function cut(op)
    parts[#parts + 1] = table.concat(cur); ops[#parts] = op; cur = {}
  end
  while i <= n do
    local c = line:sub(i, i)
    if q then
      if c == q then q = nil
      elseif c == "\\" and q == '"' then cur[#cur + 1] = c; i = i + 1; c = line:sub(i, i) end
      cur[#cur + 1] = c
    elseif c == "'" or c == '"' then
      q = c; cur[#cur + 1] = c
    elseif c == "\\" then
      cur[#cur + 1] = line:sub(i, i + 1); i = i + 1
    elseif c == "$" and line:sub(i + 1, i + 1) == "(" then
      local e = closeParen(line, i + 1)
      cur[#cur + 1] = line:sub(i, e); i = e
    elseif c == ";" then
      cut(";")
    elseif line:sub(i, i + 1) == "&&" or line:sub(i, i + 1) == "||" then
      cut(line:sub(i, i + 1)); i = i + 1
    elseif c == "&" then
      cut("&")
    elseif c == "#" and (i == 1 or line:sub(i - 1, i - 1):match("%s")) then
      break
    else
      cur[#cur + 1] = c
    end
    i = i + 1
  end
  parts[#parts + 1] = table.concat(cur)
  return parts, ops
end

-- A directory typed as a command is entered (fish's auto-cd), but only
-- when it looks like a path, so a missing command never moves you.
local function autocdTarget(name)
  if not (name:find("/") or name == "." or name == ".." or name == "~") then return nil end
  local p = shell.normalize(name)
  if fs.isDirectory(p) then return p end
end

function shell.commandExists(name)
  return shell.builtins[name] ~= nil or shell.aliases[name] ~= nil or shell.keywords[name] ~= nil
      or shell.functions[name] ~= nil or shell.resolveBin(name) ~= nil or autocdTarget(name) ~= nil
end

-- ---- Wildcards -----------------------------------------------------------
local function globPattern(seg)
  local p = seg:gsub("[%^%$%(%)%%%.%+%-]", "%%%0")
  if not p:find("%[.*%]") then p = p:gsub("%[", "%%[") end -- a lone [ is just a character
  p = p:gsub("%[!", "[^")
  return "^" .. p:gsub("%*", ".*"):gsub("%?", ".") .. "$"
end

-- The paths matching a word with * ? [...] in it, sorted, or nil if none
-- match (the word is then passed on as it is, like sh does). Names that
-- start with a dot only match a pattern that starts with one.
function shell.glob(word)
  local absolute = word:sub(1, 1) == "/"
  local found = { { show = absolute and "" or nil, real = absolute and "/" or (_G.PWD or "/") } }
  local segs = {}
  for seg in word:gmatch("[^/]+") do segs[#segs + 1] = seg end
  local function join(show, name)
    if show == nil then return name end
    return (show == "" and "" or show) .. "/" .. name
  end
  for _, seg in ipairs(segs) do
    local nextList = {}
    for _, f in ipairs(found) do
      if seg:find("[*?%[]") then
        local pat = globPattern(seg)
        for _, e in ipairs(fs.list(f.real) or {}) do
          local name = e:gsub("/$", "")
          if (seg:sub(1, 1) == "." or name:sub(1, 1) ~= ".") and name:match(pat) then
            nextList[#nextList + 1] = { show = join(f.show, name), real = shell.normalize(f.real .. "/" .. name) }
          end
        end
      else
        nextList[#nextList + 1] = { show = join(f.show, seg), real = shell.normalize(f.real .. "/" .. seg) }
      end
    end
    found = nextList
  end
  local out = {}
  for _, f in ipairs(found) do
    if fs.exists(f.real) then out[#out + 1] = f.show end
  end
  table.sort(out)
  return #out > 0 and out or nil
end

-- Words from tokenize with their wildcards replaced by the matching paths.
local function globWords(words, globs)
  local args = {}
  for i, w in ipairs(words) do
    local matches = globs[i] and shell.glob(w)
    if matches then
      for _, m in ipairs(matches) do args[#args + 1] = m end
    else
      args[#args + 1] = w
    end
  end
  return args
end

-- A line's words as a command gets them: variables, $(cmd) and wildcards expanded.
function shell.expandWords(line) return globWords(tokenize(line)) end

-- ---- Pipes and redirection -------------------------------------------------
-- Input and output of the script or `sh -c` that is running (ctx().ambient):
-- its commands read from / write to these unless they redirect themselves.

-- Splits a command at | and takes out < > >> with their file names, all
-- outside quotes. Returns stages { cmd, inp, out, append } or nil, error.
function shell.parsePipeline(line)
  local stages, stage, cur = {}, {}, {}
  local i, n, q = 1, #line, nil
  local function target()
    while line:sub(i, i):match("%s") do i = i + 1 end
    local j, wq = i, nil
    while j <= n do
      local d = line:sub(j, j)
      if wq then
        if d == wq then wq = nil elseif d == "\\" and wq == '"' then j = j + 1 end
      elseif d == "'" or d == '"' then wq = d
      elseif d == "\\" then j = j + 1
      elseif d == "$" and line:sub(j + 1, j + 1) == "(" then j = closeParen(line, j + 1)
      elseif d:match("%s") or d == "|" or d == ">" or d == "<" then break end
      j = j + 1
    end
    local word = tokenize(line:sub(i, j - 1))[1]
    i = j
    return word and shell.normalize(word)
  end
  while i <= n do
    local c = line:sub(i, i)
    if q then
      if c == q then q = nil
      elseif c == "\\" and q == '"' then cur[#cur + 1] = c; i = i + 1; c = line:sub(i, i) end
      cur[#cur + 1] = c; i = i + 1
    elseif c == "'" or c == '"' then
      q = c; cur[#cur + 1] = c; i = i + 1
    elseif c == "\\" then
      cur[#cur + 1] = line:sub(i, i + 1); i = i + 2
    elseif c == "$" and line:sub(i + 1, i + 1) == "(" then
      local e = closeParen(line, i + 1)
      cur[#cur + 1] = line:sub(i, e); i = e + 1
    elseif c == "|" then
      stage.cmd = table.concat(cur); stages[#stages + 1] = stage
      stage, cur = {}, {}; i = i + 1
    elseif c == ">" or c == "<" then
      local op = line:sub(i, i + 1) == ">>" and ">>" or c
      i = i + #op
      local t = target()
      if not t then return nil, "missing file name after " .. op end
      if op == "<" then stage.inp = t else stage.out, stage.append = t, op == ">>" end
    else
      cur[#cur + 1] = c; i = i + 1
    end
  end
  stage.cmd = table.concat(cur); stages[#stages + 1] = stage
  if #stages > 1 then
    for _, st in ipairs(stages) do
      if not st.cmd:match("%S") then return nil, "empty command in a pipe" end
    end
  end
  return stages
end

-- What a program reads: the previous stage's output or a < file as text,
-- or the keyboard when there is neither.
local function makeStdin(text)
  local s, pos = { isTerminal = text == nil }, 1
  function s.read(fmt)
    local all = fmt == "a" or fmt == "*a"
    if not text then
      if not all then return term.read() end
      local lines = {}
      while true do
        local l = term.read()
        if l == nil then break end
        lines[#lines + 1] = l .. "\n"
      end
      return table.concat(lines)
    end
    if pos > #text then return nil end
    if all then
      -- the whole input as it is: no copy (it can be large)
      local r = pos == 1 and text or text:sub(pos)
      pos = #text + 1
      return r
    end
    local e = text:find("\n", pos, true) or #text + 1
    local l = text:sub(pos, e - 1)
    pos = e + 1
    return l
  end
  function s.lines() return function() return s.read("l") end end
  return s
end

-- A stand-in for term while output goes to a pipe or a file: text is
-- collected in `buf` (colours dropped); size, keys and the rest still go to
-- the real terminal. term.read() reads from stdin.
local function makeTerm(buf, stdin)
  local t = setmetatable({}, { __index = term })
  if buf then
    local col = 1
    function t.write(s)
      s = tostring(s)
      buf[#buf + 1] = s
      local tail = s:match("[^\n]*$")
      col = (s:find("\n", 1, true) and 1 or col) + term.ulen(tail)
    end
    function t.cwrite(_, s) t.write(s) end
    function t.print(...)
      local p = table.pack(...)
      for i = 1, p.n do
        if i > 1 then t.write("\t") end
        t.write(tostring(p[i]))
      end
      t.write("\n")
    end
    function t.getCursor() return col, select(2, term.getCursor()) end
    function t.setCursor() end
    function t.clear() end
  end
  if not stdin.isTerminal then
    function t.read() return stdin.read("l") end
  end
  return t
end

-- Run fn with `io` ({ input = text, output = list }) as the default input and
-- output of the commands it executes.
function shell.withIO(io, fn, ...)
  local c = ctx()
  local saved = c.ambient
  c.ambient = io or {}
  local res = table.pack(pcall(fn, ...))
  c.ambient = saved
  if not res[1] then error(res[2], 0) end
  return table.unpack(res, 2, res.n)
end

-- ---- Jobs ------------------------------------------------------------------
-- jobs: the background jobs of this session
function shell.builtins.jobs()
  for _, j in ipairs(shell.jobs) do
    local info = k.process.info(j.pid)
    local state = (info and info.state == "running") and "Running" or "Done"
    out.write(("[%d]  %-8s %5d  %s\n"):format(j.id, state, j.pid, j.cmd))
  end
  return 0
end

-- wait [%job|pid...]: until those (or all) background jobs have ended
function shell.builtins.wait(args)
  local pids = {}
  for _, a in ipairs(args) do
    local id = a:match("^%%(%d+)$")
    if id then
      for _, j in ipairs(shell.jobs) do if j.id == tonumber(id) then pids[#pids + 1] = j.pid end end
    elseif tonumber(a) then
      pids[#pids + 1] = tonumber(a)
    end
  end
  if #args == 0 then for _, j in ipairs(shell.jobs) do pids[#pids + 1] = j.pid end end
  local ev = k.event
  ev.interruptible = ev.interruptible + 1
  local ok, err = pcall(function()
    for _, pid in ipairs(pids) do
      while (k.process.info(pid) or {}).state == "running" do k.event.pull(0.25) end
    end
  end)
  ev.interruptible = ev.interruptible - 1
  if not ok then
    if err == "interrupted" then term.cwrite(T.muted, "^C\n"); return 130 end
    error(err, 0)
  end
  return 0
end

-- fg [%job]: wait for a background job in the foreground (the newest one
-- without an argument); Ctrl+C stops it. A job never reads the keyboard,
-- so this is waiting with the option to cancel.
function shell.builtins.fg(args)
  local job, idx
  local want = args[1] and tonumber((args[1]:gsub("^%%", "")))
  for i, j in ipairs(shell.jobs) do
    if (want and j.id == want) or (not want and i == #shell.jobs) then job, idx = j, i end
  end
  if not job then shell.err("fg", args[1] and (args[1] .. ": no such job") or "no current job"); return 1 end
  out.write(job.cmd .. "\n")
  local ev = k.event
  ev.interruptible = ev.interruptible + 1
  local ok, err = pcall(function()
    while (k.process.info(job.pid) or {}).state == "running" do k.event.pull(0.25) end
  end)
  ev.interruptible = ev.interruptible - 1
  table.remove(shell.jobs, idx)
  contexts[job.pid] = nil
  if not ok then
    if err ~= "interrupted" then error(err, 0) end
    k.process.kill(job.pid)
    term.cwrite(T.muted, "^C\n")
    return 130
  end
  local info = k.process.info(job.pid) or {}
  if info.state == "killed" then return 143 end
  if info.state == "failed" then return 1 end
  return tonumber(info.result) or 0
end

-- ---- Scripts ---------------------------------------------------------------
-- Run a script: every line as if typed, with $0 = the script and $1... its
-- arguments. `exit n` ends it with status n; Ctrl+C stops it.
function shell.runScript(path, args, io)
  local src, e = fs.readAll(path)
  if not src then shell.err("byteshell", path .. ": " .. tostring(e)); return 1 end
  local c = ctx()
  local saved = c.params
  c.params = { [0] = path }
  for i, a in ipairs(args or {}) do c.params[i] = a end
  local ok, rc = pcall(shell.withIO, io, shell.execute, src)
  c.params = saved
  if not ok then
    if rc == "__exit__" then return shell.exitCode or shell.status end
    error(rc, 0)
  end
  return rc
end

-- ---- Running commands ------------------------------------------------------
-- Run one simple command (no ; && || |). io.input is text for its stdin,
-- io.output a list collecting what it prints. Returns its exit status.
function shell.run(line, io)
  io = io or {}
  line = line:gsub("^%s+", ""):gsub("%s+$", "")
  if line == "" then return 0 end

  -- fish's `not cmd` inverts the status
  local rest = line:match("^not%s+(.+)$")
  if rest then return shell.run(rest, io) == 0 and 1 or 0 end

  line = shell.expandAliases(line)
  local words, globs = tokenize(line)
  if #words == 0 then return 0 end
  -- NAME=value on its own sets a variable (as in /etc/profile)
  if #words == 1 and line:match("^[%w_]+=") then
    local name, value = words[1]:match("^([%w_]+)=(.*)$")
    return assign("byteshell", name, value)
  end
  local args = globWords(words, globs)
  local cmd = table.remove(args, 1)

  if shell.functions[cmd] then return shell.callFunction(cmd, args, io) end

  local stdin = makeStdin(io.input)
  local t = (io.output or io.input) and makeTerm(io.output, stdin) or term

  if shell.builtins[cmd] then
    local prev = out
    out = t
    local ok, rc = pcall(shell.builtins[cmd], args, io)
    out = prev
    if not ok then error(rc, 0) end
    return rc
  end

  local path = shell.resolveBin(cmd)
  if not path then
    local dir = #args == 0 and autocdTarget(cmd)
    if dir then return shell.builtins.cd({ dir }) end
    shell.err("byteshell", "Unknown command: " .. cmd)
    return 127
  end

  local src, err = readProgram(path)
  if not src then shell.err("byteshell", "cannot read " .. path .. ": " .. tostring(err)); return 1 end
  if src:sub(1, 2) == "#!" and not src:match("^#![^\n]*lua") then
    return shell.runScript(path, args, io)
  end

  local env = setmetatable({
    arg = args, shell = shell, term = t, print = t.print, fs = fs, k = k,
    stdin = stdin, stdio = io,
  }, { __index = _G })
  local fn, perr = load(src, "=" .. path, "t", env)
  if not fn then shell.err("byteshell", "parse error: " .. perr); return 1 end

  -- Ctrl+C while the program waits for a key or an event stops it
  local ev = k.event
  local fg = k.process.isForeground() -- background jobs never get Ctrl+C
  if fg then ev.interruptible = (ev.interruptible or 0) + 1 end
  local ok, rc = pcall(fn, table.unpack(args))
  if fg then ev.interruptible = ev.interruptible - 1 end
  -- programs may leave colours behind; reset to the defaults
  term.setForeground(T.fg); term.setBackground(T.bg)
  if not ok then
    if rc == "__logout__" then error(rc, 0) end -- from a nested shell
    if rc == "interrupted" then
      term.cwrite(T.muted, "^C\n")
      shell.interrupted = true
      return 130
    end
    shell.err(cmd, tostring(rc))
    return 1
  end
  return tonumber(rc) or 0
end

-- Write (or with append, add) text to a > / >> target; false after an error.
local function writeOut(path, append, text)
  local ok, e
  if append then
    local f
    f, e = fs.open(path, "a")
    if f then f:write(text); f:close(); ok = true end
  else
    ok, e = fs.writeAll(path, text)
  end
  if not ok then shell.err("byteshell", path .. ": " .. tostring(e)); return false end
  return true
end

-- a | b < in > out: the stages run one after another, each one's output
-- becoming the next one's input. Returns the last stage's status.
function shell.pipeline(line)
  local stages, perr = shell.parsePipeline(line)
  if not stages then shell.err("byteshell", perr); return 2 end
  local ambient = ctx().ambient
  local input, rc = ambient.input, 0
  for i, st in ipairs(stages) do
    if st.inp then
      local data, e = fs.readAll(st.inp)
      if not data then shell.err("byteshell", st.inp .. ": " .. tostring(e)); return 1 end
      input = data
    end
    local last = i == #stages
    local buf = (st.out or not last) and {} or ambient.output
    -- the first stage reads the script's input: `read` takes lines from it
    rc = shell.run(st.cmd, { input = input, output = buf, ambient = i == 1 and not st.inp })
    if shell.interrupted then return rc end
    if st.out then
      if not writeOut(st.out, st.append, table.concat(buf)) then return 1 end
      input = ""
    elseif not last then
      input = #buf == 1 and buf[1] or table.concat(buf) -- one piece: no copy
    end
  end
  return rc
end

-- Start a command line as a background job: prints "[1] 7" (job, pid).
function shell.background(cmd)
  cmd = cmd:gsub("^%s+", ""):gsub("%s+$", "")
  local pid, err = k.process.spawn(shell.execute, { name = cmd }, cmd)
  if not pid then shell.err("byteshell", err); return 1 end
  local id = 1
  for _, j in ipairs(shell.jobs) do id = math.max(id, j.id + 1) end
  shell.jobs[#shell.jobs + 1] = { id = id, pid = pid, cmd = cmd }
  out.write(("[%d] %d\n"):format(id, pid))
  return 0
end

-- "[1]  Done   cmd" for jobs that ended since the last prompt.
function shell.reportJobs()
  local keep = {}
  for _, j in ipairs(shell.jobs) do
    local info = k.process.info(j.pid)
    if info and info.state == "running" then
      keep[#keep + 1] = j
    else
      local how = "Done"
      if info and info.state == "killed" then how = "Killed"
      elseif info and info.state == "failed" then how = "Failed"
      elseif info and tonumber(info.result) and tonumber(info.result) ~= 0 then how = "Exit " .. info.result end
      term.cwrite(T.muted, ("[%d]  %-10s %s\n"):format(j.id, how, j.cmd))
      contexts[j.pid] = nil
    end
  end
  shell.jobs = keep
end

-- Run a command line: lists separated by ; or &, each list a && b || c
-- of pipelines. A list ending in & runs in the background as a whole.
-- Sets (in the foreground) and returns $status.
local function executeList(line)
  local parts, ops = shell.split(line or "")
  local fg = k.process.isForeground()
  local rc = shell.status
  local first = 1
  for i = 1, #parts do
    local op = ops[i]
    if op ~= "&&" and op ~= "||" then -- end of a list: ; & or the line
      if op == "&" then
        local text = {}
        for j = first, i do
          text[#text + 1] = (parts[j]:gsub("^%s+", ""):gsub("%s+$", ""))
          if j < i then text[#text + 1] = ops[j] end
        end
        rc = shell.background(table.concat(text, " "))
      else
        local go = true
        for j = first, i do
          if go and parts[j]:match("%S") then
            rc = shell.pipeline(parts[j])
            if fg then shell.status = rc end
            if shell.interrupted then return rc end
          end
          if ops[j] == "&&" then go = rc == 0 elseif ops[j] == "||" then go = rc ~= 0 end
        end
      end
      first = i + 1
    end
  end
  return rc
end

-- ---- Blocks and scripting built-ins (/lib/shellblocks.lua) --------------
-- if/while/for/function and test, read, math... live in their own module,
-- loaded the first time a command line needs them.
shell.keywords = { ["if"] = true, ["else"] = true, ["end"] = true, ["while"] = true, ["for"] = true,
  ["in"] = true, ["function"] = true, ["begin"] = true, ["and"] = true, ["or"] = true, ["not"] = true }
shell.functions = {}   -- name -> parsed body

shell._internal = {
  executeList = executeList, ctx = ctx, assign = assign, writeOut = writeOut,
  closeParen = closeParen, READONLY = READONLY,
  out = function() return out end, -- where built-ins print right now
}

local function blocks() return require("shellblocks") end

-- Statements that start with these need the block module.
local BLOCK_WORDS = { ["if"] = true, ["else"] = true, ["end"] = true, ["while"] = true, ["for"] = true,
  ["function"] = true, ["begin"] = true, ["and"] = true, ["or"] = true, ["break"] = true,
  ["continue"] = true, ["return"] = true }
local function usesBlocks(src)
  if src:find("\\\r?\n") then return true end -- a continued line
  for seg in (src .. "\n"):gmatch("([^;\n]*)[;\n]") do
    if BLOCK_WORDS[seg:match("^%s*([%w_%-]+)") or ""] then return true end
  end
  return false
end

function shell.statements(src) return blocks().statements(src) end
function shell.parse(src) return blocks().parse(src) end
function shell.incomplete(src) return usesBlocks(src) and blocks().incomplete(src) or nil end
function shell.callFunction(...) return blocks().callFunction(...) end

-- Run shell source: one line typed at the prompt, `sh -c`, a script or a
-- file read with source. Returns (and in the foreground sets) $status.
-- Lines without blocks run directly, without loading the block module.
function shell.execute(src)
  src = src or ""
  if usesBlocks(src) then return blocks().execute(src) end
  if not src:find("\n", 1, true) then return executeList(src) end
  local rc = shell.status
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    rc = executeList((line:gsub("\r$", "")))
    if shell.interrupted then break end
  end
  return rc
end

shell.builtins["true"] = function() return 0 end
shell.builtins["false"] = function() return 1 end
for _, name in ipairs({ "functions", "break", "continue", "return", "test", "[", "read", "math" }) do
  shell.builtins[name] = function(...) return blocks().builtins[name](...) end
end

-- ---- Interactive editing (see /lib/lineedit.lua) -------------------------
-- Colours as in fish: command blue (red if unknown), options cyan,
-- strings yellow, variables magenta, operators and comments muted.
local function colorWord(word, add)
  local base = word:sub(1, 1) == "-" and T.cyan or T.fg
  local i, n = 1, #word
  while i <= n do
    local c = word:sub(i, i)
    if c == "'" or c == '"' then
      local e = word:find(c, i + 1, true) or n
      add(word:sub(i, e), T.yellow); i = e + 1
    elseif c == "$" then
      local e = word:sub(i + 1, i + 1) == "(" and closeParen(word, i + 1)
        or (word:find("[^%w_{}?]", i + 1) or n + 1) - 1
      add(word:sub(i, e), T.magenta); i = e + 1
    else
      local e = (word:find("['\"$]", i) or n + 1) - 1
      add(word:sub(i, e), base); i = e + 1
    end
  end
end

function shell.highlight(buf)
  local out = {}
  local function add(text, color) if text ~= "" then out[#out + 1] = { text, color } end end
  local i, n, wantCmd = 1, #buf, true
  local forIn -- after `for`: which word comes next (the name is 1, `in` is 2)
  while i <= n do
    local c, two = buf:sub(i, i), buf:sub(i, i + 1)
    if c:match("%s") then
      local j = buf:find("%S", i) or n + 1
      add(buf:sub(i, j - 1), T.fg); i = j
    elseif two == "&&" or two == "||" then
      add(two, T.accent); i = i + 2; wantCmd = true
    elseif c == ";" or c == "|" then
      add(c, T.accent); i = i + 1; wantCmd = true
    elseif c == ">" or c == "<" then
      local op = two == ">>" and two or c
      add(op, T.accent); i = i + #op
    elseif c == "#" and (i == 1 or buf:sub(i - 1, i - 1):match("%s")) then
      add(buf:sub(i), T.muted); break
    else
      local j, q = i, nil
      while j <= n do
        local d = buf:sub(j, j)
        if q then
          if d == q then q = nil elseif d == "\\" and q == '"' then j = j + 1 end
        elseif d == "'" or d == '"' then q = d
        elseif d == "\\" then j = j + 1
        elseif d == "$" and buf:sub(j + 1, j + 1) == "(" then j = closeParen(buf, j + 1)
        elseif d:match("%s") or d == ";" or d == "|" or d == ">" or d == "<" or buf:sub(j, j + 1) == "&&" then
          break
        end
        j = j + 1
      end
      local word = buf:sub(i, math.min(j - 1, n))
      if wantCmd and shell.keywords[word] then
        -- a command follows these; for, function, end... take plain words
        add(word, T.accent)
        wantCmd = word == "if" or word == "while" or word == "else" or word == "and"
          or word == "or" or word == "not" or word == "begin"
        forIn = word == "for" and 1 or nil
      elseif forIn and word == "in" and forIn == 2 then
        add(word, T.accent); forIn = nil
      elseif wantCmd then
        local name = shell.tokenize(word, true)[1] or word
        add(word, shell.commandExists(name) and T.blue or T.red)
        wantCmd = false
      else
        if forIn then forIn = forIn + 1 end
        colorWord(word, add)
      end
      i = j
    end
  end
  return out
end

-- The newest history line that starts with what was typed.
function shell.suggest(buf)
  for i = #shell.history, 1, -1 do
    local h = shell.history[i]
    if #h > #buf and h:sub(1, #buf) == buf then return h end
  end
end

local function packageNames()
  local names = {}
  for _, f in ipairs(fs.list("/var/lib/pacman/sync") or {}) do
    if f:match("%.db$") then
      for n in (fs.readAll("/var/lib/pacman/sync/" .. f) or ""):gmatch("name = (%S+)") do names[n] = true end
    end
  end
  for _, d in ipairs(fs.list("/var/lib/pacman/local") or {}) do names[(d:gsub("/$", ""))] = true end
  return names
end

-- Tab completion: commands in command position, $VARIABLES, package names
-- after `pacman`, and paths everywhere else.
function shell.complete(before)
  local startByte = (before:match("^.*()[%s;&|]") or 0) + 1
  local word, head = before:sub(startByte), before:sub(1, startByte - 1)
  local found, seen = {}, {}
  local function offer(s, prefix)
    if s:sub(1, #prefix) == prefix and not seen[s] then seen[s] = true; found[#found + 1] = s end
  end
  local cmdPos = head:match("^%s*$") or head:match("[;&|]%s*$")
      or head:match("^%s*sudo%s+$") or head:match("[;&|]%s*sudo%s+$") or head:match("not%s+$")

  if word:sub(1, 1) == "$" then
    for name, v in pairs(_G) do
      if shell.validName(name) and type(v) == "string" then offer("$" .. name, word) end
    end
  elseif cmdPos and not word:find("/") then
    for b in pairs(shell.builtins) do offer(b, word) end
    for a in pairs(shell.aliases) do offer(a, word) end
    for f in pairs(shell.functions) do offer(f, word) end
    for dir in (_G.PATH or "/bin"):gmatch("[^:]+") do
      for _, e in ipairs(fs.list(dir) or {}) do
        if not e:match("/$") then offer((e:gsub("%.lua$", "")), word) end
      end
    end
  elseif head:match("pacman%s") and not word:match("^%-") and not word:find("/") then
    for n in pairs(packageNames()) do offer(n, word) end
  else
    local dirPart, base = word:match("^(.*/)([^/]*)$")
    if not dirPart then dirPart, base = "", word end
    local real = dirPart == "" and (_G.PWD or "/")
      or shell.normalize((dirPart:gsub("^~", _G.HOME or "/")))
    for _, e in ipairs(fs.list(real) or {}) do
      local name = e:gsub("/$", "")
      if base:sub(1, 1) == "." or name:sub(1, 1) ~= "." then
        offer(dirPart .. name .. (fs.isDirectory(real .. "/" .. name) and "/" or ""), word)
      end
    end
  end
  table.sort(found)
  return term.ulen(head) + 1, found
end

-- ---- Prompt and REPL -----------------------------------------------------
-- fish's prompt_pwd: ~ for home, every directory but the last cut to its
-- first letter (two for dot-directories).
function shell.promptPwd()
  local pwd, home = _G.PWD or "/", _G.HOME
  if home and home ~= "/" then
    if pwd == home then return "~" end
    if pwd:sub(1, #home + 1) == home .. "/" then pwd = "~" .. pwd:sub(#home + 1) end
  end
  local parts = {}
  for seg in pwd:gmatch("[^/]+") do parts[#parts + 1] = seg end
  for i = 1, #parts - 1 do
    if parts[i] ~= "~" then
      parts[i] = term.usub(parts[i], 1, parts[i]:sub(1, 1) == "." and 2 or 1)
    end
  end
  return (pwd:sub(1, 1) == "/" and "/" or "") .. table.concat(parts, "/")
end

-- fish-style prompt:  alice@byteos ~/p/projekt>   (root: red, ends in #;
-- a failed last command shows its status: [1])
function shell.prompt()
  local user = _G.USER or "root"
  local root = user == "root"
  -- never start the prompt in the middle of a line left by a program
  if term.getCursor() > 1 then term.write("\n") end
  term.cwrite(root and T.red or T.green, user)
  term.cwrite(T.fg, "@" .. (_G.HOSTNAME or "byteos") .. " ")
  term.cwrite(root and T.red or T.green, shell.promptPwd())
  if shell.status ~= 0 then term.cwrite(T.red, " [" .. shell.status .. "]") end
  term.cwrite(T.fg, root and "# " or "> ")
end

-- Login: load this user's history, then run /etc/profile and ~/.shrc.
-- A real login (not su) also runs ~/.profile, once, after them.
-- Aliases, functions and the greeting start fresh so nothing carries over
-- from the previous user.
function shell.startup(login)
  shell.aliases = {}
  shell.functions = {}
  shell.status = 0
  _G.GREETING = nil
  shell.loadHistory()
  local home = _G.HOME or "/"
  local files = { "/etc/profile", home .. "/.shrc" }
  if login then files[#files + 1] = home .. "/.profile" end
  for _, f in ipairs(files) do
    if fs.exists(f) then
      local ok, e = pcall(shell.source, f)
      if not ok then
        if e == "__exit__" or e == "__logout__" then error(e, 0) end
        shell.err(f, e)
      end
    end
  end
  shell.status = 0
end

-- Like fish_greeting: set GREETING in ~/.shrc to change it, GREETING= to
-- turn it off.
function shell.greeting()
  local g = _G.GREETING
  if g == nil then
    term.cwrite(T.fg, "Welcome to ")
    term.cwrite(T.accent, "ByteShell")
    term.cwrite(T.fg, ", the friendly interactive shell\n")
    term.cwrite(T.muted, "Type ")
    term.cwrite(T.blue, "help")
    term.cwrite(T.muted, " for commands; Tab completes, → takes the grey suggestion\n")
  elseif g ~= "" then
    term.write(g .. "\n")
  end
end

-- Read and run commands until exit, logout or Ctrl+D. A nested shell
-- (StarShell) passes logout on to the login shell and ends on exit.
function shell.loop(prompt, nested)
  prompt = prompt or shell.prompt
  local lineedit = require("lineedit")
  if k.process.tty() then k.process.tty().title = shell.promptPwd() end
  while true do
    shell.reportJobs()
    prompt()
    local line = lineedit.read({
      history = shell.history, highlight = shell.highlight,
      suggest = shell.suggest, complete = shell.complete, prompt = prompt,
    })
    term.setForeground(T.fg)
    if line == nil then return end
    -- an open block (if, for, ...) asks for more lines, indented by depth
    local open = shell.incomplete(line)
    while open do
      local function more() term.cwrite(T.muted, string.rep("  ", open)) end
      more()
      local nextLine = lineedit.read({ highlight = shell.highlight, complete = shell.complete, prompt = more })
      term.setForeground(T.fg)
      if nextLine == nil then line = ""; break end -- Ctrl+D drops the block
      line = line .. "\n" .. nextLine
      open = shell.incomplete(line)
    end
    -- history keeps one line per entry: the block's statements joined by ;
    if line:find("\n", 1, true) then line = table.concat(shell.statements(line), "; ") end
    shell.addHistory(line)
    shell.interrupted = false
    -- in a window, its title says what runs (a window manager shows it)
    local window = k.process.tty()
    if window then window.title = line:match("^%s*(.-)%s*$") end
    local ok, err = pcall(shell.execute, line)
    if window then window.title = shell.promptPwd() end
    if not ok then
      if err == "__logout__" and nested then error(err, 0) end
      if err == "__exit__" or err == "__logout__" then return end
      shell.err("error", err)
      shell.status = 1
    end
  end
end

function shell.repl()
  if not pcall(shell.startup, true) then return end -- exit/logout in a startup file
  shell.greeting()
  shell.loop(shell.prompt)
end

return shell
