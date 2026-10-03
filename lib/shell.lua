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

-- ---- Tokeniser -----------------------------------------------------------
local function tokenize(line)
  local args = {}
  local i, n = 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if c == " " or c == "\t" then
      i = i + 1
    elseif c == "\"" or c == "'" then
      local j = line:find(c, i + 1, true) or n + 1
      args[#args + 1] = line:sub(i + 1, j - 1)
      i = j + 1
    else
      local j = line:find("[%s]", i) or (n + 1)
      args[#args + 1] = line:sub(i, j - 1)
      i = j
    end
  end
  return args
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

function shell.builtins.export(args)
  for _, a in ipairs(args) do
    local k_, v = a:match("([^=]+)=(.*)")
    if k_ then _G[k_] = v end
  end
  return 0
end

function shell.builtins.set()
  for _, name in ipairs({ "HOME", "HOSTNAME", "PATH", "PWD", "SHELL", "USER" }) do
    term.cwrite(T.blue, name); term.cwrite(T.muted, "=")
    term.cwrite(T.fg, tostring(_G[name]) .. "\n")
  end
  return 0
end

-- ---- Run a single command ------------------------------------------------
function shell.execute(line)
  line = (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if line == "" or line:sub(1,1) == "#" then return 0 end

  local args = tokenize(line)
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

function shell.repl()
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
