-- help - list available commands
local T = term.theme
local W = term.size()

local seen, names = {}, {}
for dir in (_G.PATH or "/bin:/usr/bin:/sbin"):gmatch("[^:]+") do
  if k.fs.isDirectory(dir) then
    for _, e in ipairs(k.fs.list(dir)) do
      local name = e:gsub("/$", ""):gsub("%.lua$", "")
      -- /sbin/init is PID 1, not something to run from the shell
      if not seen[name] and not e:match("/$") and not (dir == "/sbin" and name == "init") then
        seen[name] = true
        names[#names + 1] = name
      end
    end
  end
end
table.sort(names)

local function grid(list, color)
  local maxlen = 0
  for _, n in ipairs(list) do maxlen = math.max(maxlen, #n) end
  local colw = maxlen + 3
  local cols = math.max(1, math.floor((W - 2) / colw))
  local rows = math.ceil(#list / cols)
  for r = 1, rows do
    term.write("  ")
    for c = 1, cols do
      local n = list[(c - 1) * rows + r]
      if n then term.cwrite(color, term.pad(n, colw)) end
    end
    term.write("\n")
  end
end

term.cwrite(T.accent, (_G._OSVERSION or "ByteOS"))
term.cwrite(T.muted, ("  ·  %d commands\n\n"):format(#names))
grid(names, T.green)
term.write("\n")
term.cwrite(T.bright, "Shell built-ins\n")
grid({ ".", "alias", "cd", "exit", "export", "history", "jobs", "logout", "not", "set", "source", "unalias", "wait" }, T.yellow)
term.write("\n")
term.cwrite(T.muted, "Keys: ↑↓ history (type first to search)  → take suggestion  Tab complete\n")
term.cwrite(T.muted, "      ^A/^E start/end  ^U/^K cut  ^W word  ^L clear  ^C cancel  ^D log out\n")
term.cwrite(T.muted, "More software: ")
term.cwrite(T.blue, "pacman -Ss")
term.cwrite(T.muted, " to search, ")
term.cwrite(T.blue, "pacman -S <name>")
term.cwrite(T.muted, " to install.\n")
return 0
