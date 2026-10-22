# Scripts

A script is a text file of shell commands that ByteShell runs one after another. This
page explains how to run scripts and everything you can write in them: variables,
quoting, pipes, redirection, conditions, loops, functions and the built-in commands
made for scripts. For typing at the prompt, see [The shell](shell.md).

Everything here also works at the prompt: a script is just commands you did not want
to type again.

??? note "Coming from bash?"
    ByteShell reads mostly like `sh`, but its blocks come from fish:
    `if test $X = 1; echo yes; end` instead of `if [ ... ]; then ...; fi`.
    Other differences worth knowing:

    - Variable names must be **UPPERCASE** (`$NAME`, not `$name`).
    - There is no local scope: variables set in a script or function stay set
      afterwards, in the whole session.
    - `$(cmd)` unquoted gives **one word per line** (like fish), not one per word.
    - Pipes are not streams yet: each command finishes before the next one starts.
    - There is no `2>`: error messages always go to the screen.
    - `math 1 + 2` does arithmetic (there is no `$((...))`).

## Running a script

Write the commands into a file, for example with `edit hello.sh`:

```sh
#!/bin/sh
# hello.sh: greet someone
echo "hello, $1"
```

Then run it in one of these ways:

```sh
alice@byteos ~> sh hello.sh world        # any script, with sh
hello, world
alice@byteos ~> ./hello.sh world         # by its name: needs #!/bin/sh as first line
alice@byteos ~> sh -c 'echo one; echo two'   # a few commands without a file
alice@byteos ~> source settings.sh       # in this shell (also: . settings.sh)
```

!!! warning "The first line matters"
    A file run by its name is treated as a **Lua program** unless its first line is
    `#!/bin/sh`. Without that line, run shell scripts with `sh script`.

To run your scripts by name from anywhere, put them in a directory of your own and add
it to `PATH` in `~/.shrc`:

```sh
export PATH=$PATH:$HOME/bin
```

Inside a script:

| Name | Meaning |
|---|---|
| `$0` | the script's path |
| `$1` ... `$9` | its arguments (only single digits: `$10` is `$1` followed by `0`) |
| `$#` | how many arguments there are |
| `$@`, `$*` | all arguments |
| `$?`, `$status` | the exit status of the last command |

`exit 3` ends the script with status 3, as does `return 3`. A line ending in `\`
continues on the next line. `#` at the start of a word begins a comment.

## Quoting and expansion

Before a command runs, ByteShell replaces variables, `$(...)`, `~` and wildcards in its
words.

| Write | You get |
|---|---|
| `$NAME`, `${NAME}` | the variable's value. An empty variable disappears entirely when unquoted |
| `"text $NAME"` | one word, variables and `$(...)` expanded inside |
| `'text $NAME'` | one word, exactly as written |
| `\$`, `\ `, `\*` | the next character as it is |
| `~`, `~/notes` | your home directory (only at the start of a word) |
| `$(command)` | what the command prints, without the trailing newline. Unquoted, **each line** becomes one word; in `"double quotes"` it is all one word |
| `$@` | unquoted: one word per argument; in `"double quotes"`: all of them as one word |

Quotes can sit in the middle of a word: `alias ll='ls -l'` is one word `ll=ls -l`.

### Wildcards

`*` (any text), `?` (one character) and `[abc]` / `[!abc]` match file names:

```sh
alice@byteos ~> ls /bin/s*.lua
alice@byteos ~> rm notes/*.bak
alice@byteos ~> echo '*'          # quoted: just a star
```

Names starting with a dot are only matched by a pattern that starts with a dot. If
nothing matches, the word is passed on unchanged (like `sh`).

## Pipes and redirection

```sh
alice@byteos ~> ls /bin | grep pac               # | feeds one command's output into the next
alice@byteos ~> pacman -Q > installed.txt        # > writes a file
alice@byteos ~> echo "one more" >> notes.txt     # >> appends to it
alice@byteos ~> grep -c ByteOS < /etc/os-release # < reads a file as input
```

Built-ins redirect too (`alias > aliases.txt`). Error messages always go to the screen;
there is no `2>`.

!!! note "Pipes are not streams (yet)"
    The commands of a pipe run **one after another**: the first finishes completely,
    then its whole output goes to the second. So `journalctl -f | grep x` never shows
    anything, and `yes` stops by itself after 1000 lines when it writes into a pipe
    (enough for `yes | sudo pacman -S something`).

## Combining commands

| Write | Runs |
|---|---|
| `a; b` | `a`, then `b` |
| `a && b` | `b` only if `a` succeeded (status 0) |
| <code>a &#124;&#124; b</code> | `b` only if `a` failed |
| `not a` | `a`, with its status turned around (fish style; `!` is not used) |
| `a &` | `a` in the background (see [processes](processes.md)) |

```sh
mkdir /tmp/work && cd /tmp/work || echo "could not make it"
```

## Conditions and loops

Blocks start with a keyword and end with `end`. Their statements are separated by new
lines or `;`, so both of these work:

```sh
if test -f notes.txt; echo found; else; echo missing; end
```

```sh
if test -f notes.txt
  echo found
else
  echo missing
end
```

At the prompt, an unfinished block asks for its next lines (++ctrl+d++ drops it).

### if

```sh
if test $COUNT -gt 10
  echo "many"
else if test $COUNT -gt 0
  echo "some"
else
  echo "none"
end
```

The condition is any command: its status decides (0 means yes), so
`if grep -c TODO notes.txt > /tmp/n` or `if command -v tar > /tmp/where` work too
(redirected so their output does not show).

### while

```sh
set I 0
while test $I -lt 3
  echo "round $I"
  set I $(math $I + 1)
end
```

### for

```sh
for F in *.txt
  echo "$F has $(math $(wc -l < $F)) lines"
end

for N in $(seq 1 5)
  echo $N
end
```

The loop variable is a normal (UPPERCASE) variable and keeps its last value afterwards.

### break, continue, and, or

`break` leaves a loop, `continue` goes on with the next round. As statements of their
own, `and CMD` runs `CMD` only if the previous statement succeeded, `or CMD` only if it
failed:

```sh
while true
  read -p "name? " NAME
  or break               # Ctrl+D: read fails, leave the loop
  echo "hi $NAME"
end
```

A long loop pauses now and then so OpenComputers does not stop the computer, and
++ctrl+c++ stops it.

### Redirecting a whole block

`<`, `>` and `>>` after `end` apply to the whole block:

```sh
while read LINE
  echo "> $LINE"
end < /etc/motd

for X in a b c; echo $X; end > letters.txt
```

### begin

`begin; ...; end` groups commands, mostly to redirect them together.

## Functions

```sh
function greet
  echo "hello, $1 (I got $# arguments)"
  return 0
end

greet alice
```

Inside a function, `$1`... are its own arguments; `return N` leaves it with status N.
`functions` lists the defined functions and `functions -e NAME` removes one. A function
cannot take the name of a built-in command, but it can shadow a program; use
`command NAME` inside to reach the program itself:

```sh
function ls
  command ls -l $@
end
```

## Built-in commands for scripts

### test and [ ]

`test EXPR` (or `[ EXPR ]`) checks something and succeeds (status 0) when it is true:

| Expression | True when |
|---|---|
| `-e FILE` | it exists |
| `-f FILE` / `-d FILE` | it is a file / a directory |
| `-s FILE` | it is a file and not empty |
| `-L FILE` | it is a symbolic link |
| `-r FILE` | it exists (ByteOS does not check read permission here) |
| `-z TEXT` / `-n TEXT` | the text is empty / not empty |
| `A = B`, `A == B`, `A != B` | texts are equal / differ |
| `A -eq B`, `-ne`, `-lt`, `-le`, `-gt`, `-ge` | numbers compare so |
| `! X`, `( X )`, `X -a Y`, `X -o Y` | not, grouping, and, or |

Quote variables that might be empty: `test "$NAME" = alice`. Status 2 means the
expression itself was wrong.

### read

`read NAME` reads one line into `NAME`. With several names, each gets one word and the
last one gets the rest of the line. It reads from a pipe, from a file after `end <`, or
from the keyboard:

```sh
read -p "Your name: " NAME        # -p shows a prompt
read -s -p "Password: " PW        # -s hides what you type
cat /etc/hostname | read HOST     # first line of the input
```

The status is 1 when there is nothing left to read.

### math

`math EXPR` prints the result of a calculation: `+ - / // % ^ ( )`, `x` for times (an
unquoted `*` would be a wildcard), and `floor ceil abs sqrt min max pi`:

```sh
alice@byteos ~> math 2 + 3 x 4
14
alice@byteos ~> math "7 / 2"
3.5
alice@byteos ~> set N $(math $N + 1)
```

### More built-ins

| Built-in | What it does |
|---|---|
| `true`, `false` | succeed / fail, nothing else |
| `eval ARGS` | run the arguments as a command line (their `$VARIABLES` are expanded once more) |
| `exec CMD...` | run `CMD`, then end the script (or the shell!) with its status. At the prompt, `exec` logs you out afterwards |
| `shift [N]` | drop the first N (default 1) arguments: `$2` becomes `$1`. Status 1 if there were not that many |
| `trap 'CMD' EXIT` | run `CMD` when the script ends, however it ends (`exit`, an error, ++ctrl+c++) |
| `trap 'CMD' INT` | run `CMD` when ++ctrl+c++ stops a command, then go on with the next command. `CMD` may `exit`. `trap '' INT` just goes on |
| `trap - EXIT` / `trap - INT` | forget a trap; `trap` alone lists them. Only EXIT and INT can be trapped |
| `type NAME...` | is it an alias, keyword, function, built-in or program (and where)? |
| `command -v NAME...` | where a program is (a built-in's name), status 1 if there is none |
| `command -V NAME...` | like `type` |
| `command NAME ARGS` | run the program or built-in `NAME`, skipping a function or alias of that name |
| `umask [MODE]` | show or set the permissions new files do not get (`umask 077`: private). It lasts until you log out |
| `set`, `export`, `NAME=value` | variables (see [The shell](shell.md)) |
| `source FILE`, `. FILE` | run a file in this shell |
| `cd`, `alias`, `history`, `jobs`, `wait`, `fg`, `exit`, `logout` | as at the prompt |

!!! note "trap INT in ByteOS"
    The command that ++ctrl+c++ hit is still stopped; with an INT trap only the script
    carries on. Without one, ++ctrl+c++ ends the script as usual (status 130).

## Text tools

These commands are made for scripts and work on files or on their input from a pipe.
Each has a manual page (`man sort`) and an entry in the
[command reference](../reference/commands.md):

`grep head tail wc sort uniq cut tr sed diff cmp tee xargs seq basename dirname
sha256sum base64 printf tac rev nl paste mktemp`

`grep` and `sed` use **Lua patterns** rather than regular expressions: `%d` is a digit,
`%a` a letter, `.` any character, `-` is "as few as possible" and `%` escapes. See
[`grep`](../reference/commands.md#grep) and [`sed`](../reference/commands.md#sed).

## Example scripts

### Count lines

```sh
#!/bin/sh
# count.sh: the lines of every .txt file here, and the total
set TOTAL 0
for F in *.txt
  if not test -f $F
    echo "no .txt files here"
    exit 1
  end
  set N $(math $(wc -l < $F))
  echo "$F: $N lines"
  set TOTAL $(math $TOTAL + $N)
end
echo "total: $TOTAL"
```

`wc -l` pads its number with spaces; passing it through `math` gives a plain number.
When no file matches, the pattern stays `*.txt` itself, which the `test -f` catches.

### A small menu

```sh
#!/bin/sh
# menu.sh: pick something to look at
while true
  echo "1) disk space   2) memory   3) quit"
  read -p "> " CHOICE
  or break
  if test "$CHOICE" = 1
    df
  else if test "$CHOICE" = 2
    free
  else if test "$CHOICE" = 3
    break
  else
    echo "pick 1, 2 or 3"
  end
end
```

### Back up your notes to a floppy

```sh
#!/bin/sh
# backup.sh: pack ~/notes into a dated archive on a backup disk
set DEST /mnt/1a2b3c4d                 # your disk: see lsblk
if not test -d $DEST
  echo "no backup disk at $DEST"
  exit 1
end
if not test -f /usr/bin/tar.lua
  echo "this needs tar: sudo pacman -S tar"
  exit 1
end
set NAME notes-$(date +%Y-%m-%d).tar
tar -cf $DEST/$NAME -C $HOME notes && echo "saved $DEST/$NAME"
```

Run it every night with `crontab -e` and a line like `0 3 * * * sh ~/backup.sh`
(see [Programs, services and logs](processes.md)).

### Clean up, whatever happens

```sh
#!/bin/sh
# report.sh: work in a temporary file that is always removed
set TMP $(mktemp)
trap 'rm $TMP' EXIT
ls -l /etc > $TMP
grep shrc $TMP || echo "nothing found"
```

The `trap` removes the file when the script ends, also when it fails or you press
++ctrl+c++.
