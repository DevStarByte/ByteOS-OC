# Lua

Everything in ByteOS is written in Lua, and you can use it too: try things out at the
`lua` prompt, run Lua files, or write your own commands. This page shows how, and which
parts of the system your code can use.

## The lua prompt

Type `lua` to get a prompt where every line you type runs at once:

```text
alice@byteos ~> lua
Lua 5.3  ·  exit or Ctrl+D to leave
> 1 + 2
3
> computer.freeMemory() // 1024
312
> t = { 1, "a", ok = true }
> t
{ 1, "a", ok = true }
> function double(x)
>>   return x * 2
>> end
> double(21)
42
> exit
```

- An **expression** shows its value. Tables are shown one level deep (at most 20
  entries). `=expr` works as well, as in older Lua versions.
- An **unfinished statement** (a function, a loop, an `if`) continues on the next line
  with a `>>` prompt.
- **Variables stay** for the whole session.
- ++arrow-up++ / ++arrow-down++ go through what you typed, also in earlier sessions:
  the history is kept in `~/.lua_history` (the newest 200 entries).
- ++ctrl+c++ clears the line you are typing, or stops code that is waiting (for example
  in `k.event.pull`). A loop that never waits cannot be interrupted; OpenComputers stops
  it after a few seconds by itself.
- `exit` or ++ctrl+d++ leaves.

## Running Lua code

```sh
alice@byteos ~> lua script.lua one two          # a file; its arguments in arg and ...
alice@byteos ~> lua -e 'print(2 ^ 10)'          # code from the command line (several -e allowed)
alice@byteos ~> echo 'print("hi")' | lua -      # code from a pipe
alice@byteos ~> lua -v                          # the Lua version
```

A file that returns a number ends with that exit status (`return 1`). Errors are
printed as `lua: message` and give status 1. A `#!` first line is ignored.

## What your code can use

At the prompt, in `lua` files and in commands you write, these are at hand:

| Name | What it is |
|---|---|
| `component` | OpenComputers' components: `component.list("gpu")`, `component.proxy(address)` |
| `computer` | the computer: `computer.uptime()`, `computer.freeMemory()`, `computer.totalMemory()`, `computer.energy()`, `computer.beep(hz, seconds)` |
| `k`, `kernel` | the ByteOS kernel: files, events, processes, users (below) |
| `fs` | the same as `kernel.fs`: the file system |
| `term` | the terminal: writing, colours, reading keys and lines |
| `shell` | ByteShell: `shell.normalize(path)`, `shell.execute("ls /")`, `shell.err(prog, msg)` |
| `require` | load a library from `/lib` or `/usr/lib`, e.g. `require("json")` from the lua-json package |

Your code runs as you, with your permissions: a normal user cannot write to `/bin` or
read `/etc/shadow` from Lua either.

### Files

All paths are absolute; `shell.normalize("notes.txt")` turns a relative one into an
absolute path from the current directory.

```lua
fs.exists("/etc/hostname")             -- true / false
fs.isDirectory("/home")                -- true / false
fs.list("/etc")                        -- { "fstab", "hostname", ..., "systemd/" } (directories end in /)
local text = fs.readAll("/etc/motd")   -- the whole file, or nil and a reason
fs.writeAll("/tmp/out.txt", "hello\n") -- replace a file
fs.makeDirectory("/tmp/a")
fs.remove("/tmp/a")                    -- a file, or a directory with everything in it
fs.rename("/tmp/x", "/tmp/y")
fs.size("/etc/motd")                   -- bytes

local f = fs.open("/tmp/log.txt", "a") -- "r", "w" or "a"
f:write("one more line\n")
f:close()

for line in fs.open("/etc/passwd", "r"):lines() do print(line) end
```

`fs.stat(path)` gives `{ owner, group, mode }`, and there are `fs.chmod`, `fs.chown`,
`fs.link`, `fs.readlink` and `fs.realpath` for permissions and
[links](files.md).

### The terminal

```lua
term.write("plain text\n")
term.cwrite(term.theme.green, "green text\n")   -- write in a colour
print("print works too", 42)
local w, h = term.size()
term.clear()
term.setCursor(1, 1)
local line = term.read()                        -- a line from the keyboard (nil on Ctrl+D)
local secret = term.read({ mask = "*" })        -- typing shows *
```

The theme's colours are `fg bg dim muted bright accent blue cyan green yellow orange
red magenta`, plus `ok warn err`. Use them instead of fixed RGB numbers, so your program
looks right on every screen tier.

### Events and waiting

```lua
local ev, addr, char, code = k.event.pull(5)          -- wait up to 5 s for any signal
local _, _, ch, code = k.event.pull(nil, "key_down")  -- wait for a key press
k.event.pull(0.5)                                     -- sleep half a second
```

While your program waits in `k.event.pull`, background processes and services get
their turn, and ++ctrl+c++ can stop your program (it raises the error `"interrupted"`).

### Other kernel functions

```lua
k.user()                               -- who is running this: "alice"
k.uptime()                             -- seconds since the computer started
k.log("backup finished", "mybackup")   -- a line in the system log (journalctl -u mybackup)
k.process.spawn(function()             -- run something in the background
  while true do k.event.pull(60); k.log("still here", "ticker") end
end, { name = "ticker" })
k.process.list()                       -- what ps shows
```

### Components

```lua
for address, kind in component.list() do print(kind, address) end

local addr = component.list("redstone")()     -- the first redstone card, or nil
if addr then
  local rs = component.proxy(addr)
  rs.setOutput(1, 15)                         -- side 1 (top) fully on
end
```

Several things are easier with ready-made commands: `lshw` (package) shows every
component, `redstone`, `power`, `robot` and `holo` (packages) cover common hardware.

### JSON

The [lua-json](../packages/list.md) package adds a JSON library, handy with web APIs:

```lua
local json = require("json")
json.encode({ name = "alice", tags = { "a", "b" } })   --> {"name":"alice","tags":["a","b"]}
local data = json.decode(fs.readAll("/tmp/answer.json"))
```

## Writing your own commands

A command is a Lua file in a directory on `PATH`. The name without `.lua` is the
command. As a normal user, make a `~/bin` of your own:

```sh
alice@byteos ~> mkdir ~/bin
alice@byteos ~> echo 'export PATH=$PATH:$HOME/bin' >> ~/.shrc
alice@byteos ~> source ~/.shrc
alice@byteos ~> edit ~/bin/greet.lua
```

```lua
--[[
  greet - say hello

    greet [NAME...]   greet everyone named, or the world
]]--
local args = arg or {}
if #args == 0 then args = { "world" } end
for _, name in ipairs(args) do
  term.cwrite(term.theme.green, "hello, " .. name .. "\n")
end
return 0
```

```sh
alice@byteos ~> greet alice bob
hello, alice
hello, bob
alice@byteos ~> man greet          # the comment at the top is the manual page
```

What a command gets:

| Name | What it is |
|---|---|
| `arg` (and `...`) | the arguments, already expanded by the shell (wildcards, variables) |
| `term` | the terminal, or a stand-in that collects the text when the output goes into a pipe or a file: keep using `term.write` and it ends up in the right place |
| `stdin` | the input: `stdin.read("a")` all of it, `stdin.read("l")` one line, `stdin.lines()`, `stdin.isTerminal` (true when it is the keyboard) |
| `stdio.output` | not nil when the output goes into a pipe or a file |
| return value | the exit status (a number; nothing means 0). An error gives status 1 and `greet: message` |

To work in pipes like the other text tools, read `stdin.read("a")` when no files are
given:

```lua
-- upper - print files (or the input) in capital letters
local text = #arg > 0 and fs.readAll(shell.normalize(arg[1])) or stdin.read("a") or ""
term.write(text:upper())
```

Root can put commands into `/usr/bin` for everyone; to share them properly, make a
[package](../packages/making.md).

## Memory and time

OpenComputers computers are small. A few habits keep your programs working on them:

- **Memory**: a Tier 1.5 memory stick gives a few hundred KiB for everything. Read big
  files in pieces with `f:lines()` or `f:read(n)` instead of `fs.readAll`, don't keep
  large tables around, and only `require` libraries you actually need.
  `computer.freeMemory()` tells you how much is left.
- **Let the machine breathe**: OpenComputers stops a computer that runs for a few
  seconds without waiting ("too long without yielding"). In a long loop, call
  `k.event.pull(0)` now and then; that also lets ++ctrl+c++ stop your program.
- **Component calls cost time**: drawing on the screen or talking to a component is
  slow compared to plain Lua. Draw whole lines rather than single characters.
