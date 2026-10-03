-- The interactive shell, driven by key presses: history search, grey
-- suggestions, Tab completion, colours, the prompt.
users()
put("/home/alice/.byteshell_history", "pacman -Q\nls /etc\necho seeded suggestion\npacman -Ss cow\n")
_G.HOME, _G.PWD = "/home/alice", "/home/alice"

local function session(keyList)
  keys(keyList)
  term.clear()
  local okRepl, err = pcall(function() as("alice", shell.repl) end)
  ok(okRepl, "repl ended cleanly: " .. tostring(err))
  return screen()
end

test("prompt_pwd shortens like fish", function()
  for path, want in pairs({ ["/home/alice"] = "~", ["/home/alice/projects/byteos"] = "~/p/byteos",
      ["/usr/share/figlet"] = "/u/s/figlet", ["/"] = "/", ["/home/alice/.config/x"] = "~/.c/x" }) do
    _G.PWD = path
    eq(shell.promptPwd(), want, path)
  end
end)

test("↑ searches the history for what was typed", function()
  local s = session({ "pac", "<up>", "<up>", "<down>", "<enter>", "<ctrl+d>" })
  has(s, "alice@byteos ~> pacman -Ss cow")
end)

test("the grey suggestion is taken with End", function()
  local s = session({ "echo se", "<end>", "<enter>", "<ctrl+d>" })
  has(s, "alice@byteos ~> echo seeded suggestion\nseeded suggestion")
end)

test("Tab completes commands and variables, lists ambiguous ones", function()
  local s = session({ "ec", "<tab>", "$US", "<tab>", "<enter>", "ex", "<tab>", "<ctrl+c>", "<ctrl+d>" })
  has(s, "echo $USER\nalice")
  has(s, "exit    export")
end)

test("status in the prompt; history file updated, leading space skipped", function()
  local s = session({ "nosuch", "<enter>", " echo secret", "<enter>", "<ctrl+d>" })
  has(s, "alice@byteos ~ [127]>")
  local h = file("/home/alice/.byteshell_history")
  has(h, "nosuch"); lacks(h, "secret")
end)

test("the line is coloured as it is typed", function()
  local chunks = shell.highlight('echo "hi $USER" -n && nosuch | grep x > out # c')
  local seen = {}
  for _, c in ipairs(chunks) do seen[#seen + 1] = c[1] .. "=" .. (c[2] == term.theme.blue and "cmd" or c[2] == term.theme.red and "bad"
    or c[2] == term.theme.yellow and "str" or c[2] == term.theme.cyan and "opt" or c[2] == term.theme.accent and "op"
    or c[2] == term.theme.muted and "comment" or "fg") end
  local line = table.concat(seen, " ")
  has(line, "echo=cmd"); has(line, '"hi $USER"=str'); has(line, "-n=opt"); has(line, "&&=op")
  has(line, "nosuch=bad"); has(line, "|=op"); has(line, "grep=cmd"); has(line, ">=op"); has(line, "# c=comment")
end)

test("aliases from ~/.shrc, gone for the next user", function()
  put("/home/alice/.shrc", "alias hi='echo hi from alice'\nGREETING=\n")
  local s = session({ "hi", "<enter>", "<ctrl+d>" })
  has(s, "hi from alice"); lacks(s, "Welcome to ByteShell", "GREETING= turns the greeting off")
  keys({ "hi", "<enter>", "<ctrl+d>" })
  term.clear()
  as("bob", shell.repl)
  has(screen(), "Unknown command: hi")
end)
