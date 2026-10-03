# ByteOS

> An Arch-Linux-flavoured operating system for the **OpenComputers** Minecraft mod.

ByteOS reimagines Arch Linux inside a virtual computer running on Lua 5.3/5.4.
You get a familiar layout (`/bin`, `/etc`, `/home`, `/usr`, `/var`), a shell modelled on
**fish**, an Arch-style **`pacman`** package manager that also updates the OS itself,
users with `sudo`, services, **`neofetch`**, an `init` system that prints `[ OK ]` lines,
the works.

```
   ____        _        ___  ____
  | __ ) _   _| |_ ___ / _ \/ ___|
  |  _ \| | | | __/ _ \ | | \___ \
  | |_) | |_| | ||  __/ |_| |___) |
  |____/ \__, |\__\___|\___/|____/
         |___/
```

## Quick install

Everything happens inside Minecraft:

1. Build a computer with an **internet card** and a blank **hard disk**.
2. Put the **OpenOS floppy** in (craft a floppy disk together with the
   OpenComputers manual) and turn the computer on.
3. In the OpenOS shell, type these two lines:

   ```
   wget -f https://raw.githubusercontent.com/DevStarByte/ByteOS-OC/master/install.lua /tmp/install.lua
   /tmp/install.lua
   ```

4. Answer the questions. Pressing Enter takes the default, except for erasing
   the disk, which you have to confirm with `yes`:

   | Question | Answer |
   |---|---|
   | Source | `1` (the internet) |
   | Which one is the target | the number of your hard disk |
   | Continue? (the disk will be erased) | `yes` |
   | Flash ByteBIOS onto the EEPROM? | Enter (yes) |
   | Reboot now? | Enter (yes) |

5. Take the OpenOS floppy out. ByteOS boots, and on the first start asks for a
   root password and a user name.

That's it. From then on, `sudo pacman -Syu` keeps ByteOS up to date.
More details and other ways to install are under
[Installing inside Minecraft](#installing-inside-minecraft-opencomputers).

## Features

- **ByteBIOS** — flashable EEPROM bootloader that finds and boots `/init.lua`.
- **bytekernel** — VFS with mountable component filesystems, cooperative process
  scheduler, signal/event loop, `require()` package loader.
- **systemd-style init** — prints `[ OK ]` boot messages, loads core libs, drops to
  a login prompt seeded from `/etc/passwd`.
- **ByteShell** — an interactive shell modelled on fish: syntax highlighting
  while you type, grey autosuggestions, history search with ↑, Tab completion,
  a persistent `~/.byteshell_history`, aliases, `;`/`&&`/`||` and auto-cd,
  plus pipes, redirection, wildcards and shell scripts.
- **Commands** —
  files: `ls cat cp mv rm mkdir touch find less edit grep head tail wc`;
  system: `df du free date timedatectl sleep uname hostname neofetch which env help reboot shutdown`;
  processes, services and logs: `ps kill systemctl journalctl dmesg logger`;
  help: `man` (`man <command>`, `man byteshell`, `man -k <word>`);
  users: `whoami id groups passwd su sudo useradd userdel usermod`;
  disks: `mount umount lsblk`; network: `wget curl`.
- **pacman** — `-S / -R / -Q / -Qi / -Sy / -Syu / -Ss` with a tiny on-disk repo format.
- **edit** — full-screen editor with line numbers and Lua syntax highlighting
  (`^S` save, `^Q` quit, `^K`/`^U` cut/paste line, `^G` go to line).
- **One colour theme** ([`lib/theme.lua`](lib/theme.lua)) — 16 colours, loaded
  into the GPU palette so Tier 2 and Tier 3 look identical; Tier 1 gets a
  clean black/white fallback. Every screen adapts to 50×16 up to 160×50.
- **Terminal** — UTF-8 output, blinking cursor and clipboard paste.
- **Kernel panic screen** instead of the generic OpenComputers crash screen.
- **/etc/os-release**, **/etc/issue**, **/etc/motd**, **/etc/hostname**, **/etc/passwd**, **/etc/pacman.conf**, **/etc/profile**, **/etc/fstab**.

## Repository Layout

```
ByteOS/
├── boot/
│   ├── eeprom.lua        ← flash to an EEPROM (ByteBIOS)
│   └── kernel.lua        ← kernel, loaded by /init.lua
├── init.lua              ← entry point invoked by ByteBIOS
├── sbin/init.lua         ← PID 1 / userspace init
├── lib/                  ← shell + term libs (loadable via require)
├── bin/                  ← user commands (.lua)
├── etc/                  ← system configuration
├── home/root/            ← root's home
├── var/lib/pacman/       ← pacman local DB
├── usr/share/man/        ← manual topic pages (man byteshell, man pacman.conf, ...)
└── tools/                ← PC tools: mkrepo.lua, repokey.sh, the test suite in test/
```

The pacman repositories (`core/`, `extra/`) live on the separate
[`packages`](https://github.com/DevStarByte/ByteOS-OC/tree/packages) branch, so cloning the OS doesn't pull in
every package. pacman downloads from there through the internet card.

## Installing inside Minecraft (OpenComputers)

You will need:

- A computer case (any tier)
- CPU + RAM: **Tier 2 memory is safe**, Tier 1.5 should just do. Measured
  with 64-bit Lua, ByteOS keeps about 190 KiB of code loaded at the prompt,
  and pacman adds 110-150 KiB while it runs. OpenComputers on a 64-bit
  server counts memory with a factor (`ramScaleFor64Bit`, 1.8 by default),
  so one Tier 1.5 stick gives about 460 KiB there.
- An EEPROM
- A managed hard disk drive
- A screen + keyboard + GPU (any tier)
- For installing over the internet: an **internet card** and the **OpenOS
  floppy**
- Optional: a **tier 3 data card**, so pacman can check package signatures

### Easiest way: over the internet, from OpenOS

Everything happens in the game; you don't touch the save folder. You need an
**internet card** in the computer and the **OpenOS floppy** (craft a floppy
disk together with the OpenComputers manual, or take it from creative).

1. Put a blank hard disk in the computer, insert the OpenOS floppy and start
   the computer: it boots OpenOS.
2. In the OpenOS shell type:
   ```
   wget -f https://raw.githubusercontent.com/DevStarByte/ByteOS-OC/master/install.lua /tmp/install.lua
   /tmp/install.lua
   ```
3. The installer asks which disk to install on (it offers only the ones that
   can take ByteOS), erases it after you confirm, downloads ByteOS from GitHub
   onto it and offers to flash ByteBIOS onto the EEPROM (your old BIOS is
   saved; `pacman -R bytebios` restores it).
4. Take the OpenOS floppy out and let it reboot.

Only the system itself (`/init.lua /boot /sbin /lib /bin /etc /home /var
/usr`) is installed. The installed system already knows its version, so
`sudo pacman -Syu` later only fetches what changed.

### The first start

On the very first boot ByteOS notices `/etc/.installed` is missing and runs
the full-screen setup wizard:
```
 ByteOS Setup                                            Settings
           ┌──────── Installation summary ────────┐
           │ ✓ Hostname                    byteos │
           │ ✓ Timezone                       UTC │
           │ • Root password             required │
           │ ✓ User account             root only │
           │ ──────────────────────────────────── │
           │   Install ByteOS                     │
           │   Abort and reboot                   │
           └──────────────────────────────────────┘
 ↑↓ move  Enter change  Shift+Q abort
```
Pick each entry with the arrow keys (or `1`-`9`) and Enter, set a root
password, then choose *Install ByteOS*. Your answers are written to
`/etc/hostname`, `/etc/timezone`, `/etc/passwd`, `/etc/shadow` and friends, and a
`/etc/.installed` marker is created so the wizard never runs again.
(Escape closes the Minecraft screen, so *back* is `Shift+Q` or Backspace.)
From now on every boot goes straight to the login prompt.

> Want to redo the setup? Just delete `/etc/.installed` and reboot.

### Other ways

- **From a disk instead of the internet:** put the ByteOS files on a floppy
  (or any disk), boot OpenOS, run `install.lua` from that disk and choose
  "a disk" as the source. It finds the disk with ByteOS by itself.
- **By hand:** copy `init.lua`, `boot/`, `sbin/`, `lib/`, `bin/`, `etc/`,
  `home/`, `var/` and `usr/` onto the hard disk (outside Minecraft:
  `saves/<world>/opencomputers/<disk-uuid>/`) and boot it. ByteOS also starts
  with the stock Lua BIOS.

> If you ever see `unrecoverable error init:4: /lib/core/boot.lua` after copying
> ByteOS by hand, OpenOS files are still on the disk. Erase it first, or use
> the installer, which does.

### Flash the EEPROM

ByteOS boots with the stock Lua BIOS too, so this is optional. To get
ByteBIOS, run this inside ByteOS:

```sh
root@byteos ~# pacman -S bytebios   # flash ByteBIOS (the old BIOS is saved)
root@byteos ~# pacman -R bytebios   # put the old BIOS back
```

Once ByteBIOS is on the EEPROM, `pacman -Syu` keeps it current. Another BIOS
is never replaced unless you ask for it. Before flashing, pacman compiles
ByteBIOS and checks that it fits; afterwards it reads the EEPROM back and
puts the old code back on a mismatch. If an EEPROM ever ends up unbootable,
craft a fresh Lua BIOS (EEPROM + manual) and swap it in.

Without ByteOS, from any working Lua prompt (e.g. OpenOS on a floppy):
```lua
local f = io.open("/path/to/ByteOS/boot/eeprom.lua", "r")
local code = f:read("*a"); f:close()
component.eeprom.set(code)
component.eeprom.setLabel("ByteBIOS")
-- Optional: pin the boot device
-- component.eeprom.setData(component.<your-disk>.address)
```

## A short tour

```sh
root@byteos ~# neofetch
root@byteos ~# uname -a
ByteOS byteos 1.11.1 (Iron) lua54 GNU/ByteOS

root@byteos ~# pacman -Sy
:: Synchronizing package databases...
 core                                   [##############################] 100%
 extra                                  [##############################] 100%

root@byteos ~# pacman -Ss cow
core/cowsay 0.2.0
    ascii-art talking cow

root@byteos ~# pacman -S cowsay
resolving dependencies...
looking for conflicting packages...

Packages (1) cowsay-0.2.0

:: Proceed with installation? [Y/n]
:: Processing package changes...
 (1/1) installing cowsay                [##############################] 100%

root@byteos ~# cowsay "I run Arch... ish."
 -------------------
< I run Arch... ish. >
 -------------------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||

root@byteos ~# pacman -Q
byteos 1.11.1
cowsay 0.2.0
```

## Users, permissions and sudo

Like on Linux, normal users may only change their own files: they can write
to their home directory, `/tmp` and `/mnt` (removable disks), and cannot read
`/etc/shadow`. Changing the system needs root. Users in the `wheel` group
(the setup wizard asks whether to add yours) use `sudo`:

```sh
alice@byteos ~> pacman -S cowsay
error: you cannot perform this operation unless you are root.
alice@byteos ~> sudo pacman -S cowsay
[sudo] password for alice:
alice@byteos ~> rm /bin/ls.lua
rm: cannot remove '/bin/ls.lua': permission denied
```

sudo asks for the user's own password and remembers it for 5 minutes
(`sudo -k` forgets it). Queries such as `pacman -Q`, `-Qi` and `-Ss` work for
everyone.

Managing accounts:

```sh
root@byteos ~# useradd -m -G wheel bob    # -m: home with /etc/skel; -G wheel: may sudo
root@byteos ~# passwd bob                 # new accounts are locked until they get one
root@byteos ~# usermod -aG wheel carol    # -aG add to / -rG remove from groups
root@byteos ~# userdel -r bob             # -r: remove the home too
alice@byteos ~> passwd                     # change your own password
alice@byteos ~> su bob                     # a shell as bob; exit comes back
alice@byteos ~> id                         # uid=1000(alice) gid=100(users) groups=...
```

Passwords are stored as salted SHA-256 hashes (`$sha256$512$salt$hash`). A
plain-text password from an older ByteOS is converted the next time that user
logs in.

Who you are is kept by the kernel, not by `$USER`, which is read-only.
To switch users, type `logout` (or press Ctrl+D on an empty line) to get back
to the login prompt; that also ends a remembered sudo password.

> These protections keep users from breaking the system or each other by
> accident. They are not a sandbox: OpenComputers gives every program direct
> access to the hardware through `component`, which a deliberately written
> program could use to get around them.

## ByteShell

The login shell takes its cues from [fish](https://fishshell.com/), the
friendly interactive shell:

```
alice@byteos ~/p/byteos> echo "hi $USER" && pacman -Q
alice@byteos ~ [127]>
```

The prompt shows user, host and directory, every directory but the last cut
to its first letter as in fish; after a failed command it adds the status.
While you type, the line is coloured: a real command is blue and an unknown
one red (before you press Enter), options cyan, strings yellow, variables
magenta.

- **History** is saved to `~/.byteshell_history` (500 commands, duplicates
  merged; each user has their own). A command that starts with a space is not
  saved. `history`, `history search <text>` and `history clear` manage it.
- **↑ / ↓** walk the history. With text typed, they only stop at commands
  containing it: type `pac`, press ↑, get your last pacman command.
- **Autosuggestions**: the grey text after the cursor is the newest matching
  command from your history. `→`, `End` or `Ctrl+F` take it.
- **Tab** completes commands, files and directories, `$VARIABLES` and, after
  `pacman`, package names. When it is ambiguous it lists the candidates.
- `a; b`, `a && b`, `a || b` and `not a`; `$status` (or `$?`) is the last
  exit status.
- Type a directory (`..`, `/etc`, `~/projects/`) to `cd` into it; `cd -`
  goes back.
- `set NAME value`, `set -e NAME` (fish syntax) as well as `NAME=value`.
- Keys: `Ctrl+A`/`Ctrl+E` start/end, `Ctrl+U`/`Ctrl+K` delete to start/end,
  `Ctrl+W` delete a word, `Ctrl+L` clear the screen, `Ctrl+C` cancel,
  `Ctrl+D` log out.
- The greeting can be changed with `GREETING=...` in `~/.shrc`, or turned
  off with `GREETING=`.

### Pipes, redirection, wildcards and scripts

```sh
root@byteos ~# ls /bin | grep pac            # | feeds one command into the next
root@byteos ~# cat /etc/os-release | head -n 2
root@byteos ~# pacman -Q > installed.txt     # > write a file, >> append to it
root@byteos ~# grep -c Iron < /etc/os-release
root@byteos ~# ls /bin/s*.lua                # * ? [abc] match file names
root@byteos ~# echo '*'                      # quoted: no matching
```

`grep`, `head`, `tail` and `wc` work on files or on their input; `cat`
without files copies its input. Commands in a pipe run one after another,
each one's output becoming the next one's input. Error messages still go to
the screen.

A shell script is a text file of commands. Start it with `#!/bin/sh` to run
it by name, or run any script with `sh`:

```sh
#!/bin/sh
# greet.sh
echo "$0 got $# arguments: $@"
echo "hello, $1"
exit 0
```

```sh
root@byteos ~# ./greet.sh world        # $1=world
root@byteos ~# sh greet.sh world
root@byteos ~# sh -c 'echo one; echo two'
```

`Ctrl+C` stops a program that is waiting for a key or an event, and skips the
rest of the command line (status 130). OpenComputers ends a program that
runs for seconds without waiting at all by itself.

`starshell` starts the same shell with a Starship-style two-line prompt;
`exit` goes back.

## Aliases and ~/.shrc

At every login ByteShell runs `/etc/profile` and then your `~/.shrc`, so
that is the place for aliases and variables. New users get a copy of
`/etc/skel/.shrc` with a few defaults (`ll`, `la`, `l`, `..`, `cls`):

```sh
root@byteos ~# alias up='sudo pacman -Syu'
root@byteos ~# alias
alias ..='cd ..'
alias ll='ls -l'
alias up='sudo pacman -Syu'
root@byteos ~# unalias up
root@byteos ~# source ~/.shrc        # or: . ~/.shrc
```

The shell understands `'single'` and `"double"` quotes (also mid-word, as in
`ll='ls -l'`), `\` escapes, `$VAR`/`${VAR}` and `~`. `NAME=value` sets a
variable, `export` too, and `set` lists them. Variable names are UPPERCASE
because they share the global namespace with Lua.

## Processes, services and logs

ByteOS runs programs in the background while the foreground waits (at the
prompt, in `sleep`, ...): a cooperative scheduler in the kernel, with each
process running as the user who started it.

```sh
root@byteos ~# sleep 60 && echo done &     # & runs the whole command in the background
[1] 4
root@byteos ~# jobs                         # this session's jobs
root@byteos ~# ps                           # every process
root@byteos ~# kill %1                      # or: kill 4 (yours, or any as root)
root@byteos ~# wait                         # until the jobs have finished
root@byteos ~# fg                           # wait for the newest job; Ctrl+C stops it
```

**Services** are described in `/etc/systemd/system/<name>.service`
(packages put theirs in `/usr/lib/systemd/system`):

```ini
[Unit]
Description=Backup every hour

[Service]
ExecStart=/usr/bin/backupd --quiet
User=root
Restart=on-failure
RestartSec=5
```

```sh
root@byteos ~# systemctl                       # every service and its state
root@byteos ~# systemctl start backupd
root@byteos ~# systemctl status backupd        # state, PID and the last log lines
root@byteos ~# systemctl enable --now backupd  # also start it at every boot
```

What a service prints goes to the system log. `Restart=on-failure` starts a
crashed service again (five times at most).

**Logs:** boot messages, logins, `sudo`/`su`, package changes, services and
crashed processes are written to `/var/log/messages`:

```sh
root@byteos ~# journalctl -n 20             # the last 20 lines
root@byteos ~# journalctl -u sudo           # one program or service; -f follows new lines
root@byteos ~# dmesg                        # everything since boot, with seconds since power-on
root@byteos ~# logger -t backup done        # write your own line
```

Programs in the background must wait with `k.event.pull` (as `sleep` and
`term.read` do); keyboard input always goes to the foreground.

## Time

OpenComputers' own clock is the Minecraft world's time. With an internet
card, the `timesyncd` service (on by default) fetches the real time at boot
and every hour, and your time zone applies, daylight saving time included:

```sh
root@byteos ~# timedatectl                         # local time, UTC, zone, synced or not
root@byteos ~# timedatectl set-timezone Europe/Berlin
root@byteos ~# timedatectl list-timezones
root@byteos ~# date "+%A, %d %B %Y %H:%M"
```

Without an internet card `date` shows the world's time and says so ("world").
The system log uses the real time once it is synchronized.

## Disks and network

Extra disks (a second HDD, a floppy) appear under `/mnt/<first 8 characters
of the address>`, also when you insert them while ByteOS runs, and disappear
when you take them out.

```sh
root@byteos ~# lsblk                         # disks, sizes and where they are mounted
root@byteos ~# df                            # free space per filesystem
root@byteos ~# ls /mnt/1a2b3c4d/
root@byteos ~# mount 1a2b3c4d /media         # mount a disk somewhere else (root)
root@byteos ~# umount /media
```

With an internet card, `wget URL` saves a file and `curl URL` prints it:

```sh
root@byteos ~# wget https://example.com/notes.txt
root@byteos ~# curl -s https://example.com/data.txt | grep foo
```

## Updating ByteOS

Like on Arch, `pacman -Syu` upgrades everything, including the OS itself.
The base system is the package `byteos`; with an **internet card** pacman
pulls its newest version straight from this GitHub repository:

```sh
root@byteos ~# pacman -Syu
:: Synchronizing package databases...
:: Starting full system upgrade...

Packages (2) byteos-1.11.1.g82e80f4  cowsay-0.3.0

:: Proceed with installation? [Y/n]
:: Retrieving byteos 1.11.1.g82e80f4 from DevStarByte/ByteOS-OC...
:: Upgrading byteos...
warning: /etc/motd installed as /etc/motd.new
:: Processing package changes...
:: byteos was upgraded; reboot to start the new version

root@byteos ~# pacman --rollback   # undo the last byteos upgrade
```

Upgrading byteos is built not to break the running system:

- Only files that changed upstream are downloaded, into
  `/var/cache/pacman/byteos`. Every `.lua` file is compiled before anything
  is installed; if a download or check fails, nothing is changed.
- Only OS files are replaced (`/init.lua`, `/boot`, `/sbin`, `/lib`, `/bin`,
  `/etc/os-release`, `/etc/issue`). `/home`, `/var`, user accounts, the
  hostname and your packages are left alone.
- `/etc` files you edited are kept; the new version is saved as `<file>.new`.
- Replaced files are backed up to `/var/lib/pacman/byteos/backup`. If the new
  version panics before reaching the login prompt, `/init.lua` restores the
  backup by itself.
- `byteos` is in `HoldPkg`, so `pacman -R byteos` refuses to delete the OS.

To follow a fork or another branch, change `BaseRepo` / `BaseBranch` in
`/etc/pacman.conf`. The repository must be public. GitHub allows 60
unauthenticated API calls per hour; each `-Syu` uses one, plus one more
when there is a new version.

## Writing your own packages

Packages are built from a source directory, much like Arch's `PKGBUILD` and
`makepkg`:

```
mytool/
├── PKGBUILD.lua          what the package is
├── mytool.install        optional hooks
└── files/                the files, laid out as on the target disk
    ├── usr/bin/mytool.lua
    └── etc/mytool.conf
```

```lua
-- PKGBUILD.lua
return {
  name      = "mytool",
  version   = "1.0.0",
  rel       = 1,                       -- bump when only the packaging changes
  desc      = "my cool tool",
  depends   = { "lolcat", "figlet>=1.0" }, -- installed automatically; a
                                           -- version may be given: >= <= = < >
  conflicts = { },
  backup    = { "/etc/mytool.conf" },  -- user edits survive upgrades (.pacnew)
  install   = "mytool.install",
}
```

```lua
-- mytool.install: every function is optional
function post_install(version) term.write("thanks for installing!\n") end
function post_upgrade(new, old) end
function pre_remove(version) end
function post_remove(version) end
```

Inside ByteOS, build and install it with:

```sh
root@byteos mytool# makepkg
==> Making package: mytool 1.0.0-1
==> Finished making: mytool-1.0.0-1.bpk (412 bytes)
root@byteos mytool# pacman -U mytool-1.0.0-1.bpk
```

To publish it, put the directory into `pkgs/<repo>/` on the
[`packages`](https://github.com/DevStarByte/ByteOS-OC/tree/packages) branch
and rebuild the repo on a PC (Lua 5.3+):

```sh
lua tools/mkrepo.lua --key ~/.config/byteos/repo-key.pem <checkout of the packages branch>
```

That writes `<repo>/<name>-<version>.bpk`, the database `<repo>/<repo>.db`
which `pacman -Sy` downloads, and with `--key` its signature `<repo>.db.sig`.

### Signed repositories

The database lists the SHA-256 of every package, so signing the database
vouches for every package in it (as on Arch). The signature is ECDSA (P-256,
SHA-256), made with `openssl` on a PC; ByteOS checks it against
`/etc/pacman.d/byteos.pub`. Make the key pair once:

```sh
tools/repokey.sh     # private key: ~/.config/byteos/repo-key.pem (keep it, never commit it)
                     # public key:  etc/pacman.d/byteos.pub (ships with ByteOS)
```

Checking a signature needs a **tier 3 data card** in the computer.
`SigLevel` in `/etc/pacman.conf` decides what happens:

| SigLevel | Behaviour |
|---|---|
| `Never` | signatures are ignored |
| `Optional` (default) | checked when a data card is there; otherwise a warning, and unsigned repos are fine |
| `Required` | only correctly signed databases are used |

Downloaded packages are always checked against the SHA-256 in the database,
with or without a data card.

### The `.bpk` format

A `.bpk` is a simple archive, read and written by [`lib/bpk.lua`](lib/bpk.lua):

```
BPK1
<size> <flag> .PKGINFO      package info: "key = value" lines
<size bytes>
<size> <flag> .INSTALL      optional hooks
<size bytes>
<size> <flag> /usr/bin/mytool.lua
<size bytes>
...
```

Entries are raw bytes, so any content works, including binary data. `flag` is
`-` for stored or `z` for LZW-compressed (pure Lua,
[`lib/compress.lua`](lib/compress.lua)); entries of 512 bytes or more are
compressed when that saves at least 10 %. pacman streams packages to disk
instead of holding them in memory, and checks size, CRC-32 and SHA-256
against the repo database before installing anything.

Before a package is installed, pacman checks:

- dependencies, which it installs from the repos first, including version
  requirements (`foo>=1.2`); it refuses an upgrade that would break what an
  installed package needs (`bar: depend = foo<2`)
- conflicts with installed packages (also with versions: `conflicts = { "foo<2" }`)
- files that another package or the base system already owns, or that
  already exist on disk

Handy queries: `pacman -Ql <pkg>` lists a package's files, `pacman -Qo <file>`
tells which package owns a file, and `sudo pacman -Sc` empties the download
cache.

Files the package lists under `backup` that you changed are kept. The new
version is saved as `.pacnew` on upgrade, and your copy as `.pacsave` on
removal.

## Hacking on ByteOS

Each command in `bin/` runs with these globals: `term`, `shell`, `fs`
(= `kernel.fs`), `k` (= `kernel`), `arg` (the arguments), `stdin` (its input:
`stdin.read("a")`, `stdin.lines()`) and `print`. Write a `.lua` file that
uses them and `return` an exit code. In a pipe or redirection `term.write`
goes there automatically.

Start the file with a comment: that is its manual page. `man mycmd` shows

```lua
--[[
  mycmd [-v] <file> - what it does, in one line

    -v   say more
]]--
```

### Tests

`tools/test/` boots the real kernel on a PC (a directory as the disk, a
fake screen and keyboard, extra disks, a data card) and drives the system
through the shell, as users, with key presses:

```sh
lua tools/test/run.lua            # everything (Lua 5.3+, openssl; no Minecraft, no internet)
lua tools/test/run.lua pacman     # only cases whose name contains "pacman"
lua tools/test/run.lua -v         # list every test, not just failures
```

Each case in `tools/test/cases/` runs on its own fresh copy of the system.
A case is a list of tests:

```lua
users()                                          -- root, alice (wheel), bob
test("bob cannot write to /etc", function()
  as("bob", function()
    has(run("echo x > /etc/x"), "permission denied")
  end)
end)
```

The helpers (`run`, `as`, `answers`, `keys`, `signals`, `disk`,
`useDatacard`, `file`, `put`, `eq`, `has`, ...) are described at the top of
[`tools/test/boot.lua`](tools/test/boot.lua).

A pre-commit hook runs the suite before every commit and stops the commit
when a test fails. Turn it on once per clone:

```sh
git config core.hooksPath tools/hooks
```

Commits that only touch files the tests don't cover (like this README) skip
it, and `git commit --no-verify` skips it once.

## License

MIT. See LICENSE.

> Minecraft is a trademark of Mojang AB. OpenComputers © Sangar et al.
