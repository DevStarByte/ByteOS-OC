# The shell

ByteShell is the program you type commands into after you log in. This page covers
using it interactively: the prompt, editing keys, history, completion, variables,
aliases and the files it runs at login. Writing scripts is on [Scripts](scripting.md).

ByteShell takes its cues from [fish](https://fishshell.com/), the "friendly
interactive shell": the line is coloured while you type, grey suggestions come from
your history, and ++tab++ completes. The command language itself is close to the
Linux `sh` you may know, with fish's blocks (`if ... end`).

## The prompt

```text
alice@byteos ~/p/byteos>
alice@byteos ~ [127]>
root@byteos /etc#
```

- **user@host** and the **current directory**. Your home directory shows as `~`.
  Every directory but the last is cut to its first letter, as in fish
  (`~/projects/byteos` becomes `~/p/byteos`).
- **`>`** for normal users (green), **`#`** for root (red), so you always see when you
  have full power.
- **`[127]`** appears after a command failed: it is that command's exit status
  (0 means success; 127 means "unknown command", 130 "stopped with Ctrl+C").
- When a program leaves the cursor in the middle of a line, the prompt starts on a
  new one.

## Colours while you type

Before you press ++enter++, the line is coloured so you can spot mistakes early:

| Colour | Means |
|---|---|
| blue | a command that exists (program, built-in, alias or function) |
| red | a command that does not exist (yet) |
| cyan | options, like `-l` |
| yellow | 'quoted' and "quoted" text |
| magenta | `$VARIABLES` and `$(commands)` |
| accent blue | operators `;` `|` `&&` `||` `>` and block words like `if`, `for`, `end` |
| grey | `# comments` |

## Keys

| Key | What it does |
|---|---|
| ++arrow-up++ / ++arrow-down++ | walk through your history. With text already typed, only lines containing that text count: type `pac`, press ++arrow-up++, get your last pacman command |
| ++arrow-right++, ++end++, ++ctrl+f++ | at the end of the line: take the grey suggestion |
| ++tab++ | complete; when there are several possibilities, list them |
| ++arrow-left++ / ++arrow-right++ | move the cursor |
| ++home++ / ++ctrl+a++ | start of the line |
| ++end++ / ++ctrl+e++ | end of the line |
| ++backspace++ / ++del++ | delete the character before / under the cursor |
| ++ctrl+u++ / ++ctrl+k++ | delete everything before / after the cursor |
| ++ctrl+w++ | delete the word before the cursor |
| ++ctrl+l++ | clear the screen |
| ++ctrl+c++ | cancel the line you are typing (it is not run) |
| ++ctrl+d++ | on an empty line: log out. Otherwise: delete the character under the cursor |

Pasting from the clipboard (OpenComputers' paste, usually the middle mouse button or
++insert++) inserts the first line of the clipboard at the cursor.

!!! note "Escape closes the screen"
    In Minecraft, ++escape++ closes the computer's screen, so ByteOS never relies on it.

## Suggestions and history

Every command you run is saved to `~/.byteshell_history` (each user has their own
file). The newest 500 are kept; running a command again moves it to the end instead
of storing it twice. **A command that starts with a space is not saved**, which is
handy for anything you would rather not keep.

While you type, the newest history line that starts with what you typed appears in
grey after the cursor. Press ++arrow-right++ (or ++end++, ++ctrl+f++) at the end of
the line to take it.

The `history` built-in manages the file:

```sh
alice@byteos ~> history                  # every saved command, newest first
alice@byteos ~> history search pacman    # only lines containing "pacman"
alice@byteos ~> history clear            # forget everything
```

## Tab completion

++tab++ completes the word under the cursor. What it offers depends on where you are:

- **The first word** of a command (also after `;`, `|`, `&&`, `||`, `sudo` and `not`):
  commands from `$PATH`, built-ins, aliases and functions.
- **A word starting with `$`**: variable names.
- **After `pacman`**: package names, from the synced databases and the installed
  packages.
- **Anywhere else**: files and directories. Directories get a `/` so you can keep
  going. Hidden files (starting with `.`) are only offered once you typed the dot.

If the word fits several candidates, ++tab++ completes as far as they agree and lists
them below the line.

## Moving around

```sh
alice@byteos ~> cd /etc          # change directory
alice@byteos /etc> cd -          # back to where you were (prints it)
alice@byteos ~> cd               # home
alice@byteos ~> ..               # typing a directory changes into it (auto-cd)
alice@byteos /home> ~/notes/
```

Auto-cd only happens for words that look like a path (containing a `/`, or `.`, `..`
and `~`), so a mistyped command never moves you somewhere unexpected.

## Variables

Variables hold text. ByteShell understands three ways to set one:

```sh
alice@byteos ~> NAME=world             # sh style
alice@byteos ~> set NAME world         # fish style (the value may be several words)
alice@byteos ~> export NAME=world      # the same: every variable is exported
alice@byteos ~> echo "hello $NAME"
hello world
alice@byteos ~> set -e NAME            # erase it
alice@byteos ~> set                    # list all variables
```

!!! warning "Variable names are UPPERCASE"
    Shell variables live next to Lua's own globals, so only names made of capital
    letters, digits and `_`, starting with a letter, are allowed (`NAME`, `MY_DIR2`).
    `export term=x` is refused instead of breaking the terminal library. A lowercase
    `$name` is simply empty.

A few variables matter to the system:

| Variable | Meaning |
|---|---|
| `USER`, `HOME`, `LOGNAME` | who you are and your home directory. **Read-only**: the kernel keeps who you are, so changing them would only make the prompt lie |
| `PWD`, `OLDPWD` | the current and the previous directory |
| `PATH` | where commands are looked for, separated by `:` (default `/bin:/usr/bin:/sbin`) |
| `EDITOR` | the editor programs like `crontab -e` open (default `edit`) |
| `GREETING` | the text shown when you log in (see below) |
| `status` / `?` | `$status` or `$?`: the exit status of the last command |

`env` lists the variables too, and `env NAME=value command` runs one command with an
extra variable.

## Aliases and ~/.shrc

An alias is a short name for a longer command:

```sh
alice@byteos ~> alias up='sudo pacman -Syu'
alice@byteos ~> up                     # runs sudo pacman -Syu
alice@byteos ~> alias                  # list them
alias ..='cd ..'
alias ll='ls -l'
alias up='sudo pacman -Syu'
alice@byteos ~> unalias up             # remove one (unalias -a: all)
```

An alias may use its own name (`alias ls='ls -1'`) without looping. Aliases only
replace the first word of a command.

Aliases and variables typed at the prompt are gone after you log out. To keep them,
put them in **`~/.shrc`**, which runs at every login. New users get a copy of
`/etc/skel/.shrc` with a few defaults:

```sh
# ~/.shrc - run by ByteShell at every login, after /etc/profile.
alias ll='ls -l'
alias la='ls -a'
alias l='ls -1'
alias ..='cd ..'
alias cls=clear

# export PATH=$PATH:$HOME/bin
# GREETING=           # no greeting at login (or set your own text)
```

After changing it, `source ~/.shrc` (or `. ~/.shrc`) loads it into the running shell.

### What runs at login

| File | When | For |
|---|---|---|
| `/etc/profile` | every login, first | system-wide settings (`PATH`, `EDITOR`); root edits it |
| `~/.shrc` | every login, after `/etc/profile` | your aliases and variables |
| `~/.profile` | once per login, after `~/.shrc` | things that should happen once when you log in, like showing a message. `su` skips it, `su -` runs it |

Aliases, functions and the greeting start fresh at every login, so nothing carries
over from the previous user.

### The greeting

ByteShell greets you at login. Change it in `~/.shrc`:

```sh
GREETING='Good morning, Dave.'     # your own text
GREETING=                          # no greeting at all
```

## Stopping things

++ctrl+c++ does different things depending on what is happening:

- **At the prompt**, it cancels the line you are typing.
- **While a program waits** for a key, an event or the network (like `sleep`,
  `less`, `ping`), it stops the program and skips the rest of the command line. The
  status is 130.
- **A shell loop** (`while true; end`) stops too.

A program that computes for several seconds without ever waiting cannot be stopped
this way, but OpenComputers ends it by itself ("too long without yielding").

++ctrl+d++ on an empty line logs you out, as do `logout` and `exit`.

## Background jobs

Add `&` to run a command in the background while you keep typing:

```sh
alice@byteos ~> sleep 60 && echo done &
[1] 4
alice@byteos ~> jobs          # your jobs and whether they still run
alice@byteos ~> fg            # wait for the newest job (Ctrl+C stops it)
alice@byteos ~> wait          # wait until all jobs have finished
```

The whole `a && b || c` list before the `&` runs in the background. When a job ends,
the next prompt tells you (`[1]  Done  sleep 60 && echo done`). Background jobs never
read the keyboard. More about processes, `ps`, `kill` and services is on
[Programs, services and logs](processes.md).

## StarShell

`starshell` starts the same shell with a two-line, Starship-style prompt (coloured
segments for user, host and directory). Everything else, from highlighting to
history, is ByteShell's own. `exit` returns to the normal prompt, `logout` logs out.

## Getting help

- `help` lists every command and the shell's built-in commands.
- `man <command>` shows a command's manual page, `man byteshell` the shell's own,
  `man -k <word>` searches them.
- `type NAME` says whether a name is an alias, a built-in, a function or a program
  (and where it is). `which` does the same for programs.

The same manual pages are in the [command reference](../reference/commands.md).
