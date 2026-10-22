# pacman

`pacman` installs, removes and upgrades software, and it also upgrades ByteOS
itself. If you have used Arch Linux, the options are the ones you know. This page
covers everyday use, how system upgrades work, and where packages come from.

Anything that changes the system needs root, so as a normal user you put `sudo`
in front. Queries (`-Q`, `-Ss`, `-Si`, `-Sg`) work for everyone.

## Installing and removing

```sh
alice@byteos ~> sudo pacman -S cowsay          # install a package and what it needs
alice@byteos ~> sudo pacman -S hyprbyte quickshell   # several at once
alice@byteos ~> sudo pacman -R cowsay          # remove it
```

`pacman -S` downloads the package databases by itself the first time, so you do not
have to run `pacman -Sy` before your first install. It shows what it is going to do and
asks `:: Proceed with installation? [Y/n]`; press Enter to go ahead. `--noconfirm`
skips the question (useful in scripts).

Before installing anything, pacman checks:

- **dependencies**: other packages a package needs are installed first, including
  version requirements such as `foo>=1.2`;
- **conflicts** with packages that are already installed;
- **files** that another package (or ByteOS itself) already owns, or that already exist
  on the disk.

If a check fails, nothing is installed.

### Removing what came along

pacman remembers why each package is installed: because you asked for it
(*explicitly*), or because another package needed it (*as a dependency*).
`pacman -Qi <name>` shows this as *Install Reason*.

```sh
root@byteos ~# pacman -Rs hyprbyte          # also the dependencies nothing else needs
root@byteos ~# pacman -Rn dunst             # also delete its changed config files
root@byteos ~# pacman -Rns hyprbyte         # both, as on Arch (s and n in any order)
root@byteos ~# pacman -Qdt                  # orphans: dependencies nothing needs any more
root@byteos ~# pacman -Qdtq | pacman -Rns - # remove all orphans ("-" reads the names from the pipe)
root@byteos ~# pacman -D --asdeps libnotify     # change the reason: as a dependency
root@byteos ~# pacman -D --asexplicit libnotify #   or as installed by you
```

`-s` never removes a package you installed yourself or one that another package still
needs. Packages installed before ByteOS 1.14 count as installed by you.

### Package files from a disk

```sh
root@byteos ~# pacman -U /mnt/1a2b3c4d/mytool-1.0.0-1.bpk
```

`-U` installs `.bpk` files directly, for example one you built yourself with
`makepkg` (see [Making packages](making.md)). Missing dependencies still come from the
repositories.

## Finding packages

```sh
alice@byteos ~> pacman -Ss                  # every package in the repositories
alice@byteos ~> pacman -Ss cow              # search names and descriptions
alice@byteos ~> pacman -Si tar              # details of one: version, size, dependencies
alice@byteos ~> pacman -Sg                  # package groups and their members
```

`pacman -S <group>` installs every package of a group. Some packages list *optional
dependencies*: extras that add a feature but are not required. pacman shows them after
installing, and `-Si`/`-Qi` list them, with `[installed]` next to the ones you have:

```text
Optional Deps   : gzip: tar -z for .tar.gz
```

Install them like any other package when you want the feature.

The [package list](list.md) describes every package with examples.

## Looking at what is installed

| Command | Shows |
|---|---|
| `pacman -Q` | every installed package and its version |
| `pacman -Qe` / `-Qd` | only those installed by you / as dependencies |
| `pacman -Qdt` | orphans (add `q` for names only: `-Qdtq`) |
| `pacman -Qi <pkg>` | details, including the install reason and optional dependencies |
| `pacman -Ql <pkg>` | the files a package installed |
| `pacman -Qo <file>` | which package owns a file (`byteos` for the system's own) |
| `pacman -Qg [group]` | installed packages by group |

```sh
alice@byteos ~> pacman -Qo /usr/bin/tar.lua
/usr/bin/tar.lua is owned by tar 1.1.0-1
```

## Upgrading everything

```sh
root@byteos ~# pacman -Syu
```

`-Syu` does three things in one go:

1. downloads the newest package databases (`-y`),
2. upgrades every installed package that has a newer version (`-u`),
3. upgrades **ByteOS itself**, which is the package `byteos`.

`-Sy` alone only refreshes the databases; `-Syy` and `-Syyu` are accepted as on Arch.

### How ByteOS upgrades itself

The base system is not in a repository database. With an **internet card**, pacman asks
GitHub for the newest commit of the ByteOS repository (set by `BaseRepo` and
`BaseBranch` in `/etc/pacman.conf`) and upgrades file by file from it. The version shows
as `byteos-<version>.g<commit>`.

```text
:: Retrieving byteos 1.17.1.gc76c56c from DevStarByte/ByteOS-OC...
:: Upgrading byteos...
warning: /etc/motd installed as /etc/motd.new
:: byteos was upgraded; reboot to start the new version
```

The upgrade is built not to break the running system:

- Only files that changed are downloaded. Every Lua file is compiled before anything is
  installed; if a download or a check fails, nothing changes.
- Only the OS's own files are replaced (`/init.lua`, `/boot`, `/sbin`, `/lib`, `/bin`,
  `/usr/share/man`, `/etc/os-release`, `/etc/issue`). Your home directory, `/var`, user
  accounts, the host name and your packages are left alone.
- A file in `/etc` that you edited is kept. The new version is saved next to it as
  `<file>.new`, and pacman tells you so. Compare the two and merge what you want.
- Everything that is replaced is backed up first.

Reboot afterwards to start the new version.

### Going back

```sh
root@byteos ~# pacman --rollback      # undo the last byteos upgrade
```

If the new version crashes before it reaches the login prompt, ByteOS puts the previous
version back by itself at the next boot. `pacman -R byteos` is refused: `byteos` is in
`HoldPkg`.

!!! note "ByteBIOS"
    `pacman -Syu` also keeps ByteBIOS (the boot firmware on the EEPROM) current, but only
    if ByteBIOS is already on the EEPROM. `pacman -S bytebios` flashes it and
    `pacman -R bytebios` puts the old BIOS back. See [Installing](../getting-started/install.md).

### Config files of packages

Files a package marks as configuration (its `backup` list, for example
`/etc/hyprbyte.conf`) survive upgrades: if you changed one, the new version is saved as
`<file>.pacnew` instead of replacing yours. When you remove the package, your changed
copy is kept as `<file>.pacsave` (unless you use `-Rn`).

## Repositories and pacman.conf

Packages come from two repositories:

| Repository | What is in it |
|---|---|
| `core` | small everyday tools (`lshw`, `redstone`, `timers`, `pastebin`, `gitget`, ...) |
| `extra` | bigger programs, games, the desktop, modded-Minecraft tools |

Both live on the [`packages` branch](https://github.com/DevStarByte/ByteOS-OC/tree/packages)
of the ByteOS repository. They are set in `/etc/pacman.conf`:

```ini
[options]
HoldPkg     = byteos
SigLevel    = Optional
TrustedKey  = /etc/pacman.d/byteos.pub
BaseRepo    = DevStarByte/ByteOS-OC
BaseBranch  = master

[core]
Server = https://raw.githubusercontent.com/DevStarByte/ByteOS-OC/packages/core

[extra]
Server = https://raw.githubusercontent.com/DevStarByte/ByteOS-OC/packages/extra
```

A `Server` is either an `http(s)://` URL (needs an internet card) or a directory on a
mounted disk. `man pacman.conf` describes every setting.

!!! tip "Fresh databases from GitHub"
    GitHub's file server caches files for a few minutes. pacman therefore asks GitHub for
    the branch's newest commit and downloads the database and its packages from that
    commit, so it never mixes an old database with new packages.

### An offline repository on a floppy

A computer without an internet card can install from a disk. On a PC, copy the `core/`
and `extra/` folders of the `packages` branch onto a floppy (or any disk), put it in the
computer and point the repositories at it. Extra disks appear at
`/mnt/<first 8 characters of the disk address>`; `lsblk` shows it.

```ini
[core]
Server = /mnt/1a2b3c4d/core

[extra]
Server = /mnt/1a2b3c4d/extra
```

Then `pacman -Sy` and `pacman -S <name>` work as usual. Upgrading ByteOS itself still
needs an internet card.

### Signatures

Every package database lists the SHA-256 checksum of each package, and every download
is checked against it. The database itself is signed with the ByteOS key
(`/etc/pacman.d/byteos.pub`). Checking that signature needs a **tier 3 data card** in
the computer. `SigLevel` decides what happens:

| SigLevel | Behaviour |
|---|---|
| `Never` | signatures are ignored |
| `Optional` (default) | checked when a data card is there; otherwise one warning, and unsigned repositories are accepted |
| `Required` | only correctly signed databases are used |

A `SigLevel` line inside a `[repo]` section overrides the default for that repository.

## Cleaning up

```sh
root@byteos ~# pacman -Sc       # empty the download cache (leftovers of failed installs)
```

## When something goes wrong

**`error: target not found: foo`**
:   The name is not in the databases. pacman suggests `pacman -Sy` to refresh them and
    `pacman -Ss foo` to search. If it says the databases could not be synchronized, look
    at the messages above it: usually there is no internet card, or the server could
    not be reached.

**`error: you cannot perform this operation unless you are root.`**
:   Run the same command with `sudo` in front.

**`warning: the package databases are not synchronized`**
:   A normal user ran a query before the databases were ever downloaded. Run
    `sudo pacman -Sy` once.

**`... exists in filesystem`**
:   A file the package wants to install is already on the disk (or belongs to another
    package). `pacman -Qo <file>` tells you who owns it.

**A config file was saved as `.pacnew` or `.new`**
:   Your edited copy was kept. Compare it with the new one
    (`diff /etc/foo.conf /etc/foo.conf.pacnew`) and merge what you need.

More problems and fixes are on [Troubleshooting](../getting-started/troubleshooting.md).
