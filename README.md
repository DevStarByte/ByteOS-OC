# ByteOS

> An Arch-Linux-flavoured operating system for the **OpenComputers** Minecraft mod.

ByteOS reimagines Arch Linux inside a virtual computer running on Lua 5.3/5.4.
You get a familiar layout (`/bin`, `/etc`, `/home`, `/usr`, `/var`), a colourful shell prompt
in the classic `[user@host pwd]$` style, an Arch-style **`pacman`** package manager,
**`neofetch`**, an `init` system that prints `[ OK ]` lines, the works.

```
   ____        _        ___  ____
  | __ ) _   _| |_ ___ / _ \/ ___|
  |  _ \| | | | __/ _ \ | | \___ \
  | |_) | |_| | ||  __/ |_| |___) |
  |____/ \__, |\__\___|\___/|____/
         |___/
```

## Features

- **ByteBIOS** — flashable EEPROM bootloader that finds and boots `/init.lua`.
- **bytekernel** — VFS with mountable component filesystems, cooperative process
  scheduler, signal/event loop, `require()` package loader.
- **systemd-style init** — prints `[ OK ]` boot messages, loads core libs, drops to
  a login prompt seeded from `/etc/passwd`.
- **ByteShell** — an interactive shell modelled on fish: syntax highlighting
  while you type, grey autosuggestions, history search with ↑, Tab completion,
  a persistent `~/.byteshell_history`, aliases, `;`/`&&`/`||` and auto-cd.
- **Coreutils** — `ls cat echo pwd mkdir rm cp mv clear uname whoami edit help neofetch reboot shutdown`.
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
└── tools/mkrepo.lua      ← builds the package repos (runs on a PC)
```

The pacman repositories (`core/`, `extra/`) live on the separate
[`packages`](https://github.com/DevStarByte/ByteOS-OC/tree/packages) branch, so cloning the OS doesn't pull in
every package. pacman downloads from there through the internet card.

## Installing inside Minecraft (OpenComputers)

You will need:

- A computer case (any tier)
- CPU + RAM (at least Tier 1.5; the OS is small but uses ~64 KiB)
- An EEPROM
- A managed hard disk drive
- A screen + keyboard + GPU (any tier)

### Easiest way: just copy the files onto a disk

ByteOS now has a **first-boot setup wizard**. You don't need to run any installer
script — just put the files on a disk and boot it.

1. Flash `boot/eeprom.lua` onto your EEPROM (see "Flash the EEPROM" below).
2. Copy the contents of this repository onto the target HDD so the disk root
   contains `/init.lua`, `/boot/`, `/sbin/`, `/lib/`, `/bin/`, `/etc/`, `/home/`,
   `/var/`. From outside Minecraft you can drop the files straight into
   `saves/<world>/opencomputers/<disk-uuid>/`.
3. Set the EEPROM's boot address to that disk (or just have it as the only
   bootable FS).
4. Power on. On the very first boot ByteOS notices `/etc/.installed` is missing
   and runs the full-screen setup wizard:
   ```
    ByteOS Setup                                            Settings
              ┌──────── Installation summary ────────┐
              │ ✓ Hostname                    byteos │
              │ ✓ Keyboard layout                 us │
              │ ✓ Locale                 en_US.UTF-8 │
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
   `/etc/hostname`, `/etc/passwd`, `/etc/shadow` and friends, and a
   `/etc/.installed` marker is created so the wizard never runs again.
   (Escape closes the Minecraft screen, so *back* is `Shift+Q` or Backspace.)
5. From now on every boot goes straight to the login prompt and verifies your
   password.

> Want to redo the setup? Just delete `/etc/.installed` and reboot.

### Optional: use the bundled `install.lua` from OpenOS

The old installer is still included for the case where you want to copy the
files **from another disk** (e.g. a floppy under OpenOS) and optionally flash
the EEPROM in one go:

1. Boot any OpenOS computer.
2. Insert a disk/floppy that contains this repository.
3. Insert a blank target HDD for ByteOS.
4. From the OpenOS shell run:
   ```
   lua /mnt/<id_of_byteos_disk>/install.lua
   ```
5. The installer asks for source / target FS, wipes the target, copies all
   ByteOS files and (optionally) flashes ByteBIOS. Reboot afterwards — the
   first-boot wizard above takes care of the rest.

> If you ever see `unrecoverable error init:4: /lib/core/boot.lua` after copying
> ByteOS, that means OpenOS files are still on the disk. Wipe the disk (or
> re-run `install.lua`) before copying ByteOS over it.

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
ByteOS byteos 1.3.1 (Iron) lua54 GNU/ByteOS

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
byteos 1.3.1
cowsay 0.2.0
```

## Users and sudo

Changing the system with pacman needs root. Regular users in the `wheel` group
(the setup wizard asks whether to add yours) use `sudo`, which is part of the
base system:

```sh
alice@byteos ~> pacman -S cowsay
error: you cannot perform this operation unless you are root.
alice@byteos ~> sudo pacman -S cowsay
[sudo] password for alice:
```

Like on Linux, sudo asks for the user's own password and remembers it for
5 minutes (`sudo -k` forgets it). Users outside `wheel` are refused.
Queries such as `pacman -Q`, `-Qi` and `-Ss` work for everyone.

To switch users, type `logout` (or press Ctrl+D on an empty line) to get
back to the login prompt. It also works from inside StarShell, and sudo
forgets the remembered password.

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

## Updating ByteOS

Like on Arch, `pacman -Syu` upgrades everything, including the OS itself.
The base system is the package `byteos`; with an **internet card** pacman
pulls its newest version straight from this GitHub repository:

```sh
root@byteos ~# pacman -Syu
:: Synchronizing package databases...
:: Starting full system upgrade...

Packages (2) byteos-1.3.1.g6b48868  cowsay-0.3.0

:: Proceed with installation? [Y/n]
:: Retrieving byteos 1.3.1.g6b48868 from DevStarByte/ByteOS-OC...
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
  depends   = { "lolcat" },            -- installed automatically
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
lua tools/mkrepo.lua <checkout of the packages branch>
```

That writes `<repo>/<name>-<version>.bpk` and the database `<repo>/<repo>.db`
which `pacman -Sy` downloads.

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
instead of holding them in memory, and checks size and CRC-32 against the
repo database before installing anything.

Before a package is installed, pacman checks:

- dependencies, which it installs from the repos first
- conflicts with installed packages
- files that another package or the base system already owns, or that
  already exist on disk

Files the package lists under `backup` that you changed are kept. The new
version is saved as `.pacnew` on upgrade, and your copy as `.pacsave` on
removal.

## Hacking on ByteOS

Each command in `bin/` runs in a sandbox where the following globals are pre-injected:
`term`, `shell`, `fs` (= `kernel.fs`), `k` (= `kernel`), and `arg` (the argv list).
Just write a `.lua` file that uses them and `return` an exit code.

## License

MIT. See LICENSE.

> Minecraft is a trademark of Mojang AB. OpenComputers © Sangar et al.
