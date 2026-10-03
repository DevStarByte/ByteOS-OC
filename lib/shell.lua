--[[
  /lib/shell.lua - ByteShell, an Arch-flavoured POSIX-ish shell
]]--

local k    = _G.kernel
local fs   = k.fs
local term = require("term")
local T    = term.theme

local shell = {}
shell.history = {}

-- Print an error message: "<prog>: " in red, the message in the default colour.
function shell.err(prog, msg)
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

function shell.resolveBin(name)
  if name:find("/") then return shell.normalize(name) end
  for dir in (_G.PATH or "/bin:/usr/bin:/sbin"):gmatch("[^:]+") do
    local p = dir .. "/" .. name .. ".lua"
    if fs.exists(p) then return p end
    p = dir .. "/" .. name
    if fs.exists(p) then return p end
  end
  return nil
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

-- ---- Tokeniser -----------------------------------------------------------
-- Splits a line into words like a POSIX shell (without globbing):
--   'single quotes'  everything inside is literal
--   "double quotes"  keep spaces, still expand $VAR
--   \c               the next character literally (outside single quotes)
--   $NAME ${NAME}    the variable's value
--   ~ ~/...          $HOME at the start of a word
-- Quotes may appear mid-word: ll='ls -l' is one word, "ll=ls -l".
function shell.tokenize(line)
  local args, word, inWord = {}, {}, false
  local i, n = 1, #line
  local function push(s) word[#word + 1] = s; inWord = true end
  local function finish()
    if inWord then args[#args + 1] = table.concat(word) end
    word, inWord = {}, false
  end
  local function variable(j)
    local name, nxt = line:match("^{([%w_]+)}()", j)
    if not name then name, nxt = line:match("^([%w_]+)()", j) end
    if not name then return "$", j end
    return shell.getVar(name), nxt
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
        elseif d == "$" then
          local v; v, i = variable(i + 1); push(v)
        else
          push(d); i = i + 1
        end
      end
      i = i + 1
    elseif c == "\\" then
      push(line:sub(i + 1, i + 1)); i = i + 2
    elseif c == "$" then
      -- an empty unquoted expansion adds no word, as in sh ("$X" would)
      local v; v, i = variable(i + 1)
      if v ~= "" then push(v) end
    elseif c == "~" and not inWord and (i == n or line:sub(i + 1, i + 1):match("[/%s]")) then
      push(_G.HOME or "/"); i = i + 1
    else
      push(c); i = i + 1
    end
  end
  finish()
  return args
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

function shell.builtins.cd(args)
  local target = args[1] or _G.HOME or "/"
  if target == "~" or target:sub(1, 2) == "~/" then target = (_G.HOME or "/") .. target:sub(2) end
  local p = shell.normalize(target)
  if not fs.isDirectory(p) then
    shell.err("cd", "not a directory: " .. target)
    return 1
  end
  _G.PWD = p
  return 0
end

function shell.builtins.exit() error("__exit__", 0) end

-- Back to the login prompt, even from a nested shell such as StarShell.
function shell.builtins.logout() error("__logout__", 0) end

-- NAME=value; refuses names that are not shell variables (see validName).
local function assign(prog, name, value)
  if not shell.validName(name) then
    shell.err(prog, "'" .. name .. "': not a valid variable name (use UPPERCASE)")
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
    for _, n in ipairs(names) do term.write("alias " .. n .. "=" .. quote(shell.aliases[n]) .. "\n") end
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
      term.write("alias " .. a .. "=" .. quote(shell.aliases[a]) .. "\n")
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
  local rc = 0
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    rc = shell.execute((line:gsub("\r$", "")))
  end
  return rc
end

function shell.builtins.source(args)
  if not args[1] then shell.err("source", "usage: source <file>"); return 1 end
  local rc, e = shell.source(shell.normalize(args[1]))
  if not rc then shell.err("source", e); return 1 end
  return rc
end
shell.builtins["."] = shell.builtins.source

function shell.builtins.set()
  local names = {}
  for name, v in pairs(_G) do
    if shell.validName(name) and (type(v) == "string" or type(v) == "number") then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    term.cwrite(T.blue, name); term.cwrite(T.muted, "=")
    term.cwrite(T.fg, tostring(_G[name]) .. "\n")
  end
  return 0
end

-- ---- Run a single command ------------------------------------------------
function shell.execute(line)
  line = (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if line == "" or line:sub(1,1) == "#" then return 0 end

  line = shell.expandAliases(line)
  local args = tokenize(line)
  if #args == 0 then return 0 end
  -- NAME=value on its own sets a variable (as in /etc/profile)
  if #args == 1 and line:match("^[%w_]+=") then
    local name, value = args[1]:match("^([%w_]+)=(.*)$")
    return assign("byteshell", name, value)
  end
  local cmd  = table.remove(args, 1)

  if shell.builtins[cmd] then
    return shell.builtins[cmd](args)
  end

  local path = shell.resolveBin(cmd)
  if not path then
    shell.err("byteshell", "command not found: " .. cmd)
    return 127
  end

  local src, err = fs.readAll(path)
  if not src then shell.err("byteshell", "cannot read " .. path .. ": " .. tostring(err)); return 1 end

  local env = setmetatable({ arg = args, shell = shell, term = term, fs = fs, k = k }, { __index = _G })
  local fn, perr = load(src, "=" .. path, "t", env)
  if not fn then shell.err("byteshell", "parse error: " .. perr); return 1 end

  local ok, rc = pcall(fn, table.unpack(args))
  -- programs may leave colours behind; reset to the defaults
  term.setForeground(T.fg); term.setBackground(T.bg)
  if not ok then
    if rc == "__logout__" then error(rc, 0) end -- from a nested shell
    shell.err(cmd, tostring(rc))
    return 1
  end
  return tonumber(rc) or 0
end

-- ---- REPL ----------------------------------------------------------------
-- Arch-style prompt:  [user@host ~]$   (user and # in red when root)
function shell.prompt()
  local user = _G.USER or "root"
  local host = _G.HOSTNAME or "byteos"
  local pwd  = _G.PWD or "/"
  local home = _G.HOME
  if pwd == home then pwd = "~"
  elseif home and pwd:sub(1, #home + 1) == home .. "/" then pwd = "~" .. pwd:sub(#home + 1) end
  -- keep the prompt short enough to leave room for typing on small screens
  local maxPwd = math.max(8, math.floor(term.width / 3))
  if term.ulen(pwd) > maxPwd then pwd = "…" .. term.usub(pwd, -(maxPwd - 1)) end
  local root = user == "root"
  -- never start the prompt in the middle of a line left by a program
  if term.getCursor() > 1 then term.write("\n") end
  term.cwrite(T.muted, "[")
  term.cwrite(root and T.red or T.green, user)
  term.cwrite(T.muted, "@")
  term.cwrite(T.fg, host .. " ")
  term.cwrite(T.blue, pwd)
  term.cwrite(T.muted, "]")
  term.cwrite(root and T.red or T.fg, root and "# " or "$ ")
  term.setForeground(T.bright)
end

-- Login: run /etc/profile, then the user's ~/.shrc. Aliases start empty so
-- nothing carries over from the previous user.
function shell.startup()
  shell.aliases = {}
  for _, f in ipairs({ "/etc/profile", (_G.HOME or "/") .. "/.shrc" }) do
    if fs.exists(f) then
      local ok, e = pcall(shell.source, f)
      if not ok then
        if e == "__exit__" or e == "__logout__" then error(e, 0) end
        shell.err(f, e)
      end
    end
  end
end

function shell.repl()
  if not pcall(shell.startup) then return end -- exit/logout in a startup file
  while true do
    shell.prompt()
    local line = term.read({ history = shell.history })
    term.setForeground(T.fg)
    if line == nil then return end
    local ok, err = pcall(shell.execute, line)
    if not ok then
      if err == "__exit__" or err == "__logout__" then return end
      shell.err("error", err)
    end
  end
end

return shell
