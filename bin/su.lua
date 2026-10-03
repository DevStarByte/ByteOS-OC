--[[
  su [user] - start a shell as another user (default: root)

  Asks for that user's password (root needs none). The shell loads the
  user's history and ~/.shrc; `exit` returns to where you were.
]]--
local args = arg or {}
local T = term.theme
if args[1] == "-" then table.remove(args, 1) end -- `su -` is accepted
local target = args[1] or "root"

local password
if k.user() ~= "root" then
  term.write("Password: ")
  password = term.read({ mask = "•" })
  if password == nil then term.write("\n"); return 1 end
end

-- the shell keeps one set of aliases/history; give them back afterwards
local saved = { aliases = shell.aliases, history = shell.history, status = shell.status,
                greeting = _G.GREETING }
local ok, why = k.su(target, password, function()
  local okStart, e = pcall(shell.startup)
  if not okStart and e ~= "__exit__" then error(e, 0) end
  if okStart then shell.loop(nil, true) end
end)
shell.aliases, shell.history, shell.status, _G.GREETING = saved.aliases, saved.history, saved.status, saved.greeting

if not ok then
  term.cwrite(T.err, "su: ")
  term.write(why == "unknown" and ("user " .. target .. " does not exist\n") or "Authentication failure\n")
  return 1
end
return 0
