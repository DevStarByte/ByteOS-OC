--[[
  /lib/shell.lua - ByteShell, an Arch-flavoured POSIX-ish shell
]]--

local k    = _G.kernel
local fs   = k.fs
local term = require("term")

local shell = {}

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
  local p = shell.normalize(target)
  if not fs.isDirectory(p) then
    term.write("cd: not a directory: " .. target .. "\n")
    return 1
  end
  _G.PWD = p
  return 0
end

function shell.builtins.exit() error("__exit__", 0) end

function shell.builtins.export(args)
  for _, a in ipairs(args) do
    local k_, v = a:match("([^=]+)=(.*)")
    if k_ then _G[k_] = v end
  end
  return 0
end

function shell.builtins.set()
  for name, val in pairs({ PATH = _G.PATH, HOME = _G.HOME, USER = _G.USER, PWD = _G.PWD, SHELL = _G.SHELL }) do
    term.write(name .. "=" .. tostring(val) .. "\n")
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
    term.write("byteshell: command not found: " .. cmd .. "\n")
    return 127
  end

  local src, err = fs.readAll(path)
  if not src then term.write("cannot read " .. path .. ": " .. tostring(err) .. "\n"); return 1 end

  local env = setmetatable({ arg = args, shell = shell, term = term, fs = fs, k = k }, { __index = _G })
  local fn, perr = load(src, "=" .. path, "t", env)
  if not fn then term.write("parse error: " .. perr .. "\n"); return 1 end

  local ok, rc = pcall(fn, table.unpack(args))
  if not ok then term.write(cmd .. ": " .. tostring(rc) .. "\n"); return 1 end
  return tonumber(rc) or 0
end

-- ---- REPL ----------------------------------------------------------------
function shell.prompt()
  local user = _G.USER or "root"
  local host = _G.HOSTNAME or "byteos"
  local pwd  = _G.PWD or "/"
  if pwd == _G.HOME then pwd = "~" elseif _G.HOME and pwd:sub(1, #_G.HOME) == _G.HOME then pwd = "~" .. pwd:sub(#_G.HOME + 1) end
  term.setForeground(0x55FF55); term.write("[" .. user .. "@" .. host)
  term.setForeground(0xFFFFFF); term.write(" ")
  term.setForeground(0x55AAFF); term.write(pwd)
  term.setForeground(0x55FF55); term.write("]")
  term.setForeground(0xFFFFFF); term.write(user == "root" and "# " or "$ ")
end

function shell.repl()
  while true do
    shell.prompt()
    local line = term.read()
    if line == nil then term.write("\n"); return end
    local ok, err = pcall(shell.execute, line)
    if not ok then
      if err == "__exit__" then return end
      term.write("error: " .. tostring(err) .. "\n")
    end
  end
end

return shell
