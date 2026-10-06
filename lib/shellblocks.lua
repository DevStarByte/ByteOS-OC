--[[
  /lib/shellblocks.lua - ByteShell's scripting: if/while/for/function
  blocks, and the built-ins test, [, read, math, functions, break,
  continue and return.

  /lib/shell.lua loads this the first time a command line uses one of
  them, so a session that never does keeps it out of memory.
]]--

local k = _G.kernel
local fs = k.fs
local term = require("term")
local T = term.theme
local shell = require("shell")
local I = shell._internal   -- the shell's own helpers

local M = {}
local B = {}                -- built-in commands
M.builtins = B

-- ---- Blocks: if, while, for, function (fish syntax) ---------------------
--   if CMD; ...; else if CMD; ...; else; ...; end
--   while CMD; ...; end          for NAME in WORDS; ...; end
--   function NAME; ...; end      begin; ...; end
--   break  continue  return [n]  and CMD  or CMD
-- Statements end at ; or a new line. `end` may be followed by < > or >>,
-- which then apply to the whole block (while read LINE; ...; end < file).

-- Splits source text into statements at ; and new lines outside quotes and
-- $(...); \ at the end of a line continues it, # starts a comment.
function M.statements(src)
  local list, cur = {}, {}
  local i, n, q = 1, #src, nil
  local function cut()
    local s = table.concat(cur):match("^%s*(.-)%s*$")
    if s ~= "" then list[#list + 1] = s end
    cur = {}
  end
  while i <= n do
    local c = src:sub(i, i)
    if c == "\r" then
      -- CRLF files: drop the \r
    elseif q then
      if c == q then q = nil
      elseif c == "\\" and q == '"' then cur[#cur + 1] = c; i = i + 1; c = src:sub(i, i) end
      cur[#cur + 1] = c
    elseif c == "'" or c == '"' then
      q = c; cur[#cur + 1] = c
    elseif c == "\\" then
      local d = src:sub(i + 1, i + 1)
      if d == "\n" or (d == "\r" and src:sub(i + 2, i + 2) == "\n") then
        cur[#cur + 1] = " "; i = i + #d -- a continued line
      else
        cur[#cur + 1] = c .. d; i = i + 1
      end
    elseif c == "$" and src:sub(i + 1, i + 1) == "(" then
      local e = I.closeParen(src, i + 1)
      cur[#cur + 1] = src:sub(i, e); i = e
    elseif c == ";" or c == "\n" then
      cut()
    elseif c == "#" and (#cur == 0 or cur[#cur]:match("%s$")) then
      i = (src:find("\n", i, true) or n + 1) - 1
    else
      cur[#cur + 1] = c
    end
    i = i + 1
  end
  cut()
  return list
end

local OPENS = { ["if"] = true, ["while"] = true, ["for"] = true, ["function"] = true, ["begin"] = true }

-- open: how many blocks were still open at the end of the text
local function syntax(msg, open) error({ shellSyntax = msg, open = open }, 0) end
local function firstWord(s) return s:match("^%S+") end
local function isEnd(s) return s == "end" or s:match("^end%s") ~= nil end

local parseBlock

-- The block statement at stmts[i] (if/while/for/function/begin) up to its
-- end. Returns the node and the index of that end.
local function parseCompound(stmts, i, depth)
  local s, w = stmts[i], firstWord(stmts[i])
  local function body(from)
    local b, j = parseBlock(stmts, from, depth + 1)
    if j > #stmts then syntax("missing 'end' for '" .. w .. "'", depth + 1) end
    return b, j
  end
  local function close(node, j)
    local e = stmts[j]
    if not isEnd(e) then syntax("'" .. firstWord(e) .. "' outside 'if'") end
    node.redir = e:match("^end%s+(.+)$")
    return node, j
  end
  if w == "if" then
    local cond = s:match("^if%s+(.+)$") or syntax("'if' needs a command")
    local node = { kind = "if", branches = {} }
    local j = i
    while true do
      local b
      b, j = body(j + 1)
      node.branches[#node.branches + 1] = { cond = cond, body = b }
      local t = stmts[j]
      if t == "else" then
        node.elseBody, j = body(j + 1)
        return close(node, j)
      elseif t:match("^else%s+if%s") then
        cond = t:match("^else%s+if%s+(.+)$")
      elseif isEnd(t) then
        return close(node, j)
      else
        syntax("unexpected '" .. t .. "'")
      end
    end
  elseif w == "while" then
    local cond = s:match("^while%s+(.+)$") or syntax("'while' needs a command")
    local b, j = body(i + 1)
    return close({ kind = "while", cond = cond, body = b }, j)
  elseif w == "for" then
    local var, list = s:match("^for%s+(%S+)%s+in(.*)$")
    if not var or not (list == "" or list:match("^%s")) then syntax("usage: for NAME in WORDS...") end
    local b, j = body(i + 1)
    return close({ kind = "for", var = var, list = list, body = b }, j)
  elseif w == "function" then
    local name = s:match("^function%s+(%S+)")
    if not name or shell.keywords[name] or name:find("[/$'\"]") then syntax("'function' needs a name") end
    local b, j = body(i + 1)
    return close({ kind = "function", name = name, body = b }, j)
  else -- begin
    if s ~= "begin" then syntax("nothing may follow 'begin' on its line") end
    local b, j = body(i + 1)
    return close({ kind = "begin", body = b }, j)
  end
end

-- Statements from stmts[i] up to an end/else of the enclosing block (or the
-- end of the text at depth 0). Returns the nodes and where it stopped.
parseBlock = function(stmts, i, depth)
  local nodes = {}
  while i <= #stmts do
    local s = stmts[i]
    local w = firstWord(s)
    if w == "end" or w == "else" then
      if depth == 0 then syntax("'" .. w .. "' without a block to end") end
      return nodes, i
    end
    if OPENS[w] then
      local node
      node, i = parseCompound(stmts, i, depth)
      nodes[#nodes + 1] = node
    else
      local how, rest = s:match("^(%l+)%s+(.+)$")
      if how == "and" or how == "or" then
        nodes[#nodes + 1] = { kind = "cmd", text = rest, only = how }
      else
        nodes[#nodes + 1] = { kind = "cmd", text = s }
      end
    end
    i = i + 1
  end
  return nodes, i
end

function M.parse(src) return (parseBlock(M.statements(src), 1, 0)) end

-- How many blocks the text leaves open (the prompt then asks for more
-- lines), or nil when it is complete or has a different error.
function M.incomplete(src)
  local ok, err = pcall(M.parse, src)
  if not ok and type(err) == "table" and err.open then return err.open end
end

-- break, continue and return travel up as errors to the loop or function.
local function signalOf(err) return type(err) == "table" and err.shellSignal end

-- A long loop gives the machine a moment now and then (OpenComputers
-- stops a computer that runs too long without waiting) and lets Ctrl+C
-- stop it. Returns false once it has been interrupted.
local lastBreath = 0
local function breathe()
  if shell.interrupted then return false end
  local now = k.uptime()
  if now - lastBreath < 0.5 then return true end
  lastBreath = now
  local ev = k.event
  local fg = k.process.isForeground()
  if fg then ev.interruptible = ev.interruptible + 1 end
  local ok, err = pcall(ev.pull, 0.05)
  if fg then ev.interruptible = ev.interruptible - 1 end
  if not ok then
    if err ~= "interrupted" then error(err, 0) end
    term.cwrite(T.muted, "^C\n")
    shell.interrupted = true
    return false
  end
  return true
end

local execNodes

-- Run fn with the redirections written after a block's `end`.
local function withRedir(redir, fn)
  if not redir then return fn() end
  local stages, perr = shell.parsePipeline("end " .. redir)
  if not stages or #stages ~= 1 or not stages[1].cmd:match("^%s*end%s*$") then
    shell.err("byteshell", perr or "only < > and >> may follow 'end'"); return 2
  end
  local st, ambient = stages[1], I.ctx().ambient
  local io = { input = ambient.input, output = ambient.output }
  if st.inp then
    local data, e = fs.readAll(st.inp)
    if not data then shell.err("byteshell", st.inp .. ": " .. tostring(e)); return 1 end
    io.input = data
  end
  if st.out then io.output = {} end
  local ok, rc = pcall(shell.withIO, io, fn)
  if st.out and not I.writeOut(st.out, st.append, table.concat(io.output)) and ok then rc = 1 end
  if not ok then error(rc, 0) end
  return rc
end

-- One loop pass: the body's status, or "break" / "continue".
local function loopBody(body)
  local ok, rc = pcall(execNodes, body)
  if ok then return rc end
  local sig = signalOf(rc)
  if sig == "break" or sig == "continue" then return sig end
  error(rc, 0)
end

local run = {}

function run.cmd(node, last)
  if node.only == "and" and last ~= 0 then return last end
  if node.only == "or" and last == 0 then return last end
  return I.executeList(node.text)
end

function run.begin(node) return execNodes(node.body) end

run["if"] = function(node)
  for _, b in ipairs(node.branches) do
    local c = I.executeList(b.cond)
    if shell.interrupted then return c end
    if c == 0 then return execNodes(b.body) end
  end
  if node.elseBody then return execNodes(node.elseBody) end
  return 0
end

run["while"] = function(node)
  local rc = 0
  while breathe() do
    if I.executeList(node.cond) ~= 0 or shell.interrupted then break end
    local r = loopBody(node.body)
    if r == "break" then break end
    if r ~= "continue" then rc = r end
  end
  return shell.interrupted and 130 or rc
end

run["for"] = function(node)
  if not shell.validName(node.var) then
    shell.err("for", "'" .. node.var .. "': not a valid variable name (use UPPERCASE)"); return 1
  end
  if I.READONLY[node.var] then shell.err("for", node.var .. ": read-only variable"); return 1 end
  local rc = 0
  for _, w in ipairs(shell.expandWords(node.list)) do
    if not breathe() then break end
    _G[node.var] = w
    local r = loopBody(node.body)
    if r == "break" then break end
    if r ~= "continue" then rc = r end
  end
  return shell.interrupted and 130 or rc
end

run["function"] = function(node)
  if shell.builtins[node.name] then
    shell.err("function", "'" .. node.name .. "' is a built-in command"); return 1
  end
  shell.functions[node.name] = node.body
  return 0
end

execNodes = function(nodes)
  local rc = shell.status
  local fg = k.process.isForeground()
  for _, node in ipairs(nodes) do
    if shell.interrupted then return 130 end
    rc = withRedir(node.redir, function() return run[node.kind](node, rc) end)
    if fg then shell.status = rc end
  end
  return rc
end

-- Run shell source: one line typed at the prompt, `sh -c`, a script or a
-- file read with source. Returns (and in the foreground sets) $status.
function M.execute(src)
  local ok, nodes = pcall(M.parse, src or "")
  if not ok then
    if type(nodes) ~= "table" or not nodes.shellSyntax then error(nodes, 0) end
    shell.err("byteshell", nodes.shellSyntax)
    if k.process.isForeground() then shell.status = 2 end
    return 2
  end
  local done, rc = pcall(execNodes, nodes)
  if done then return rc end
  local sig = signalOf(rc)
  if sig == "return" then return rc.rc end -- ends a script or sourced file
  if sig then shell.err(sig, "not inside a loop"); return 1 end
  error(rc, 0)
end

-- ---- Functions -------------------------------------------------------------

-- Call a function: $1... are its arguments, `return n` ends it.
function M.callFunction(name, args, io)
  local c = I.ctx()
  local saved = c.params
  c.params = { [0] = name }
  for i, a in ipairs(args) do c.params[i] = a end
  local ok, rc = pcall(shell.withIO, { input = io.input, output = io.output }, execNodes, shell.functions[name])
  c.params = saved
  if ok then return rc end
  if signalOf(rc) == "return" then return rc.rc end
  error(rc, 0)
end

-- functions          list the defined functions
-- functions -e NAME  erase one
function B.functions(args)
  if args[1] == "-e" or args[1] == "--erase" then
    local rc = 0
    for i = 2, #args do
      if shell.functions[args[i]] then shell.functions[args[i]] = nil
      else shell.err("functions", args[i] .. ": not found"); rc = 1 end
    end
    return rc
  end
  local names = {}
  for name in pairs(shell.functions) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do I.out().write(name .. "\n") end
  return 0
end

B["break"] = function() error({ shellSignal = "break" }, 0) end
B["continue"] = function() error({ shellSignal = "continue" }, 0) end
B["return"] = function(args)
  error({ shellSignal = "return", rc = tonumber(args[1]) or shell.status }, 0)
end

-- ---- test, read, math ------------------------------------------------------

local UNARY = {
  ["-e"] = function(p) return fs.exists(shell.normalize(p)) end,
  ["-f"] = function(p) p = shell.normalize(p); return fs.exists(p) and not fs.isDirectory(p) end,
  ["-d"] = function(p) return fs.isDirectory(shell.normalize(p)) end,
  ["-s"] = function(p) p = shell.normalize(p); return fs.exists(p) and not fs.isDirectory(p) and (fs.size(p) or 0) > 0 end,
  ["-r"] = function(p) return fs.exists(shell.normalize(p)) end,
  ["-z"] = function(s) return s == "" end,
  ["-n"] = function(s) return s ~= "" end,
}
local NUMERIC = {
  ["-eq"] = function(a, b) return a == b end, ["-ne"] = function(a, b) return a ~= b end,
  ["-lt"] = function(a, b) return a < b end,  ["-le"] = function(a, b) return a <= b end,
  ["-gt"] = function(a, b) return a > b end,  ["-ge"] = function(a, b) return a >= b end,
}
local STRING = {
  ["="] = function(a, b) return a == b end, ["=="] = function(a, b) return a == b end,
  ["!="] = function(a, b) return a ~= b end,
}

-- Evaluates test's arguments: ! ( ) -a -o around the checks above.
local function testExpr(a)
  local i = 1
  local orExpr
  local function primary()
    local t = a[i]
    if t == nil then error("missing argument", 0) end
    if t == "!" then i = i + 1; return not primary() end
    if t == "(" then
      i = i + 1
      local v = orExpr()
      if a[i] ~= ")" then error("missing )", 0) end
      i = i + 1
      return v
    end
    local op = a[i + 1]
    if op and (NUMERIC[op] or STRING[op]) and a[i + 2] then
      local lhs, rhs = t, a[i + 2]
      i = i + 3
      if STRING[op] then return STRING[op](lhs, rhs) end
      local x, y = tonumber(lhs), tonumber(rhs)
      if not x or not y then error("a number was expected: " .. (x and rhs or lhs), 0) end
      return NUMERIC[op](x, y)
    end
    if UNARY[t] and a[i + 1] then
      i = i + 2
      return UNARY[t](a[i - 1])
    end
    i = i + 1
    return t ~= ""
  end
  local function andExpr()
    local v = primary()
    while a[i] == "-a" do i = i + 1; local r = primary(); v = v and r end
    return v
  end
  orExpr = function()
    local v = andExpr()
    while a[i] == "-o" do i = i + 1; local r = andExpr(); v = v or r end
    return v
  end
  if #a == 0 then return false end
  local v = orExpr()
  if a[i] ~= nil then error("unexpected '" .. a[i] .. "'", 0) end
  return v
end

-- test EXPR / [ EXPR ]: status 0 if true, 1 if false, 2 on a mistake
function B.test(args, _, prog)
  local ok, v = pcall(testExpr, args)
  if not ok then shell.err(prog or "test", v); return 2 end
  return v and 0 or 1
end
B["["] = function(args, io)
  if args[#args] ~= "]" then shell.err("[", "missing ]"); return 2 end
  args[#args] = nil
  return B.test(args, io, "[")
end

-- read [-p PROMPT] [-s] NAME...: one line into NAME (with several names,
-- one word each and the rest into the last). Reads from a pipe, a file
-- after `end <`, or the keyboard; status 1 when there is nothing left.
function B.read(args, io)
  local prompt, silent, names = nil, false, {}
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "-p" or a == "-P" or a == "--prompt" then i = i + 1; prompt = args[i]
    elseif a == "-s" or a == "--silent" then silent = true
    elseif a:sub(1, 1) == "-" and #a > 1 then shell.err("read", "unknown option " .. a); return 2
    else names[#names + 1] = a end
    i = i + 1
  end
  if #names == 0 then shell.err("read", "usage: read [-p prompt] [-s] NAME..."); return 2 end
  local line
  if io and io.input ~= nil then
    local text = io.input
    if text == "" then return 1 end
    local e = text:find("\n", 1, true)
    line = e and text:sub(1, e - 1) or text
    if io.ambient then I.ctx().ambient.input = e and text:sub(e + 1) or "" end
  else
    if prompt then term.write(prompt) end
    line = term.read(silent and { mask = "*" } or nil)
    if line == nil then return 1 end
  end
  line = line:gsub("\r$", "")
  local rc = 0
  for n, name in ipairs(names) do
    local value = line
    if n < #names then value, line = line:match("^%s*(%S*)%s*(.*)$")
    elseif #names > 1 then value = line:match("^%s*(.-)%s*$") end
    if I.assign("read", name, value) ~= 0 then rc = 2 end
  end
  return rc
end

-- math EXPR: prints the result of + - * / // % ^ ( ), with x for times
-- (an unquoted * would be a wildcard) and floor ceil abs sqrt min max.
local MATHFN = { floor = math.floor, ceil = math.ceil, abs = math.abs, sqrt = math.sqrt,
  min = math.min, max = math.max, pi = math.pi }
function B.math(args)
  local expr = table.concat(args, " "):gsub("(%d)%s*x%s*", "%1*"):gsub("%)%s*x%s*", ")*")
  if not expr:match("%S") then shell.err("math", "usage: math EXPRESSION"); return 2 end
  for word in expr:gmatch("%a[%w_]*") do
    if not MATHFN[word] then shell.err("math", "unknown word '" .. word .. "'"); return 2 end
  end
  if expr:find("[^%w%s%.%+%-%*/%%%^%(%),]") then shell.err("math", "invalid expression: " .. expr); return 2 end
  local fn = load("return " .. expr, "=math", "t", MATHFN)
  local ok, v = pcall(fn or error, "invalid expression")
  if not ok or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
    shell.err("math", "invalid expression: " .. expr); return 2
  end
  if v == math.floor(v) and math.abs(v) < 2^53 then I.out().write(("%d\n"):format(v))
  else I.out().write((("%.6f"):format(v):gsub("0+$", "")) .. "\n") end
  return 0
end

return M
