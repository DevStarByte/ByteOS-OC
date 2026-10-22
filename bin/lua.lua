--[[
  lua - run Lua code, or try it out line by line

    lua                  an interactive prompt: type Lua, see the result
    lua FILE [args...]   run a file; its arguments are in `arg` and `...`
    lua -e CODE          run CODE (may be given several times)
    lua -                run what comes from a pipe: echo 'print(1)' | lua -
    lua -v               the Lua version

  At the prompt an expression shows its value (`=expr` works too, as in
  Lua 5.1), and an unfinished statement (a function, a loop) asks for its
  next lines with >>. Variables stay for the whole session. exit or
  Ctrl+D leaves; Ctrl+C clears the line, or stops code that waits
  (OpenComputers stops a loop that never waits by itself). ↑ and ↓ go
  through what you typed, also in earlier sessions (~/.lua_history).

  The code runs as you, with component, computer, require, k (the kernel),
  fs, term and shell at hand. A file that returns a number ends with that
  exit status.
]]--
local args = arg or {}
local T = term.theme

local function newEnv(a)
  return setmetatable({ k = k, kernel = k, fs = fs, term = term, shell = shell, print = print,
    stdin = stdin, arg = a, _G = _G }, { __index = _G })
end

-- Values as the prompt shows them: strings inside tables quoted, tables
-- one level deep.
local function show(v, nested)
  local t = type(v)
  if t == "string" then return nested and ("%q"):format(v):gsub("\\\n", "\\n") or v end
  if t ~= "table" or nested then return tostring(v) end
  local parts, n, seen = {}, 0, {}
  for i, x in ipairs(v) do
    seen[i] = true
    n = n + 1
    if n <= 20 then parts[#parts + 1] = show(x, true) end
  end
  local keys = {}
  for key in pairs(v) do if not seen[key] then keys[#keys + 1] = key end end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do
    n = n + 1
    if n <= 20 then
      local name = type(key) == "string" and key:match("^[%a_][%w_]*$") and key or ("[" .. show(key, true) .. "]")
      parts[#parts + 1] = name .. " = " .. show(v[key], true)
    end
  end
  if n > 20 then parts[#parts + 1] = ("... (%d more)"):format(n - 20) end
  return "{ " .. table.concat(parts, ", ") .. (#parts > 0 and " }" or "}")
end

-- Run a compiled chunk; false and the message if it failed.
local function call(fn, ...)
  local res = table.pack(pcall(fn, ...))
  if not res[1] then
    local e = res[2]
    if e == "interrupted" then return false, "interrupted" end
    return false, type(e) == "string" and e or ("error object: " .. show(e))
  end
  return true, res
end

local function runChunk(src, name, env, ...)
  src = src:gsub("^#![^\n]*", "") -- a #!/bin/lua line
  local fn, perr = load(src, "=" .. name, "t", env)
  if not fn then shell.err("lua", perr); return 1 end
  local ok, res = call(fn, ...)
  if not ok then shell.err("lua", res); return 1 end
  return math.tointeger(res[2]) or 0
end

-- ---- lua FILE / -e / - ------------------------------------------------------
local codes, i = {}, 1
while i <= #args do
  local a = args[i]
  if a == "-e" then
    i = i + 1
    if not args[i] then shell.err("lua", "'-e' needs code"); return 1 end
    codes[#codes + 1] = args[i]
  elseif a == "-v" then
    term.write(_VERSION .. " on " .. (_G._OSVERSION or "ByteOS") .. "\n")
    if #codes == 0 and not args[i + 1] then return 0 end
  elseif a == "--" then i = i + 1; break
  elseif a:sub(1, 1) == "-" and a ~= "-" then
    shell.err("lua", "unknown option " .. a); return 1
  else
    break
  end
  i = i + 1
end

local script = args[i]
local scriptArgs = { [0] = script }
for j = i + 1, #args do scriptArgs[#scriptArgs + 1] = args[j] end
local env = newEnv(scriptArgs)
for n, c in ipairs(codes) do
  local rc = runChunk(c, "(command line " .. n .. ")", env)
  if rc ~= 0 then return rc end
end
if script == "-" then
  return runChunk(stdin.read("a") or "", "stdin", env, table.unpack(scriptArgs))
elseif script then
  local path = shell.normalize(script)
  local src, err = fs.readAll(path)
  if not src or fs.isDirectory(path) then shell.err("lua", "cannot open " .. script .. ": " .. tostring(err or "a directory")); return 1 end
  return runChunk(src, script, env, table.unpack(scriptArgs))
end
if #codes > 0 then return 0 end

-- ---- the prompt -------------------------------------------------------------
local lineedit = require("lineedit")
-- the prompt's history stays in ~/.lua_history between runs (the newest
-- HISTMAX entries, as ByteShell keeps its own)
local HISTMAX = 200
local histFile = (_G.HOME or "/") .. "/.lua_history"
local history = {}
for l in ((fs.exists(histFile) and fs.readAll(histFile)) or ""):gmatch("[^\n]+") do history[#history + 1] = l end
if #history > HISTMAX then
  history = { table.unpack(history, #history - HISTMAX + 1) }
  pcall(fs.writeAll, histFile, table.concat(history, "\n") .. "\n")
end
local function remember(entry)
  if not entry:match("%S") or history[#history] == entry then return end
  history[#history + 1] = entry
  local f = fs.open(histFile, "a")
  if f then f:write(entry .. "\n"); f:close() end
end
term.cwrite(T.accent, _VERSION)
term.cwrite(T.muted, "  ·  exit or Ctrl+D to leave\n")

-- The line editor gets Ctrl+C as a key (it clears the line) instead of it
-- stopping the whole program: the shell counts interruptible up for us.
local function readLine(prompt)
  local draw = function() term.cwrite(T.accent, prompt) end
  draw()
  local ev = k.event
  local saved = ev.interruptible
  ev.interruptible = 0
  local ok, line = pcall(lineedit.read, { history = history, prompt = draw })
  ev.interruptible = saved
  term.setForeground(T.fg)
  if not ok then error(line, 0) end
  return line
end

while true do
  local line = readLine("> ")
  if line == nil or line:match("^%s*exit%s*$") or line:match("^%s*exit%(%)%s*$") then break end
  local src = line:gsub("^=", "return ")
  -- an unfinished chunk ("... near <eof>") asks for more lines
  local fn, perr
  while true do
    fn = load("return " .. src, "=stdin", "t", env)
    if not fn then fn, perr = load(src, "=stdin", "t", env) end
    if fn or not tostring(perr):find("<eof>", 1, true) then break end
    local more = readLine(">> ")
    if more == nil then fn = nil; perr = nil; break end
    src = src .. "\n" .. more
  end
  remember((src:gsub("\n", " ")))
  if fn then
    local ok, res = call(fn)
    if not ok then
      shell.err("lua", res)
    elseif res.n > 1 then
      local parts = {}
      for j = 2, res.n do parts[#parts + 1] = show(res[j]) end
      term.write(table.concat(parts, "\t") .. "\n")
    end
  elseif perr then
    shell.err("lua", perr)
  end
end
return 0
