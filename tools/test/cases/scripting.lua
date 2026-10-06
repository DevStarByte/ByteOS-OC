-- ByteShell scripting: if/while/for/function blocks, $(cmd), test, read, math.
put("/tmp/lines.txt", "alpha one\nbeta two\ngamma three\n")

test("if / else if / else, on one line and over several", function()
  eq(run("if true; echo yes; else; echo no; end"), "yes\n")
  eq(run("if false; echo yes; else if true; echo elif; else; echo no; end"), "elif\n")
  eq(run("if false\n  echo yes\nelse\n  echo no\nend"), "no\n")
  eq(run("if not false; echo inverted; end"), "inverted\n")
  local _, rc = run("if false; echo x; end")
  eq(rc, 0, "no branch taken: status 0")
end)

test("for over words, wildcards and $(cmd); break and continue", function()
  eq(run("for X in a b c; echo [$X]; end"), "[a]\n[b]\n[c]\n")
  has(run("for F in /bin/s*.lua; echo $F; end"), "/bin/sh.lua\n")
  eq(run("for N in $(seq 1 5); if test $N -eq 2; continue; end; if test $N -eq 4; break; end; echo $N; end"), "1\n3\n")
  has(run("for x in a; echo $x; end"), "'x': not a valid variable name")
end)

test("while with a counter, test and math", function()
  eq(run("I=0; while test $I -lt 3; echo i=$I; set I $(math $I + 1); end"), "i=0\ni=1\ni=2\n")
end)

test("while read over a file, a pipe and a script's input", function()
  eq(run("while read W REST; echo $W; end < /tmp/lines.txt"), "alpha\nbeta\ngamma\n")
  eq(run("cat /tmp/lines.txt | read FIRST; echo $FIRST"), "alpha one\n")
  put("/tmp/upper.sh", "#!/bin/sh\nwhile read L\n  echo \"> $L\"\nend\n")
  eq(run("cat /tmp/lines.txt | sh /tmp/upper.sh"), "> alpha one\n> beta two\n> gamma three\n")
end)

test("a block's output can be redirected after end", function()
  run("for X in 1 2; echo n$X; end > /tmp/blk.txt")
  eq(file("/tmp/blk.txt"), "n1\nn2\n")
  run("if true; echo more; end >> /tmp/blk.txt")
  eq(file("/tmp/blk.txt"), "n1\nn2\nmore\n")
end)

test("functions with arguments, return and recursion", function()
  local out = run([[
function greet
  echo "hello $1, $# args"
  return 3
end
greet world x; echo status=$status
function count
  if test $1 -gt 0
    echo $1
    count $(math $1 - 1)
  end
end
count 3
functions]])
  has(out, "hello world, 2 args\nstatus=3\n")
  has(out, "3\n2\n1\n")
  has(out, "count\ngreet\n")
  run("functions -e greet")
  has(run("greet"), "Unknown command: greet")
  has(run("function cd; end"), "'cd' is a built-in command")
end)

test("$(cmd): unquoted one word per line, quoted as one", function()
  eq(run("echo $(echo hi)!"), "hi!\n")
  eq(run('for L in $(cat /tmp/lines.txt); echo "<$L>"; end'), "<alpha one>\n<beta two>\n<gamma three>\n")
  eq(run('echo "$(echo a; echo b)"'), "a\nb\n")
  eq(run("echo $(echo 'a;b|c')"), "a;b|c\n", "; and | inside $() stay inside")
  eq(run("X=$(exit 4); echo after"), "after\n", "exit only ends the substitution")
end)

test("and / or statements, test and [ ]", function()
  eq(run("false; and echo no; or echo yes"), "yes\n")
  eq(run("[ -d /etc ] && echo dir; [ -f /etc ] || echo notfile; test -e /nope; or echo missing"), "dir\nnotfile\nmissing\n")
  eq(run("test abc = abc -a ! 1 -gt 2 && echo ok"), "ok\n")
  eq(run("test -z ''; and test -n x; and echo empty"), "empty\n")
  has(run("test 1 -lt x"), "a number was expected: x")
  has(run("[ 1 = 1"), "missing ]")
end)

test("math", function()
  eq(run("math 1 + 2 x 3"), "7\n")
  eq(run("math '(1 + 2) * 3' / 2"), "4.5\n")
  eq(run("math 'max(3, 9) % 4'"), "1\n")
  has(run("math 1 / 0"), "invalid expression")
  has(run("math os.exit"), "unknown word 'os'")
end)

test("syntax errors and stray break", function()
  has(run("if true; echo x"), "missing 'end' for 'if'")
  has(run("end"), "'end' without a block to end")
  has(run("while true; else; end"), "'else' outside 'if'")
  has(run("break"), "break: not inside a loop")
  eq(shell.incomplete("for X in a\n  if true"), 2, "two blocks still open")
  eq(shell.incomplete("for X in a; end"), nil)
end)

test("Ctrl+C stops an endless loop", function()
  signals({ { "key_down", "kbd", 0, 29 }, { "key_down", "kbd", 0, 46 } })
  local out, rc = run("while true; end")
  eq(rc, 130); has(out, "") -- returned at all
end)

test("scripts: blocks over several lines, return ends the script", function()
  put("/tmp/blocks.sh", "#!/bin/sh\n# a comment\nfor A in $@\n  if test $A = stop\n    return 5\n  end\n  echo got $A\nend\necho never\n")
  local out, rc = run("/tmp/blocks.sh one two stop three")
  eq(out, "got one\ngot two\n"); eq(rc, 5)
end)

test("highlighting knows keywords and leaves $() unrun", function()
  put("/tmp/ran", "")
  local parts = shell.highlight("for X in $(echo x > /tmp/ran2); echo $X; end")
  ok(not file("/tmp/ran2"), "highlighting must not run $()")
  eq(parts[1][1], "for"); eq(parts[1][2], term.theme.accent)
  local words = {}
  for _, p in ipairs(parts) do words[p[1]] = p[2] end
  eq(words["in"], term.theme.accent); eq(words["end"], term.theme.accent)
  eq(words["echo"], term.theme.blue)
end)

test("plain command lines do not load the block module (memory)", function()
  package.loaded.shellblocks = nil
  run("echo a; ls /etc | grep x; X=1; true && false || echo b")
  eq(package.loaded.shellblocks, nil)
  eq(shell.incomplete("echo a"), nil)
  eq(package.loaded.shellblocks, nil, "typing a plain line neither")
  run("if true; end")
  ok(package.loaded.shellblocks, "a block loads it")
end)
