# Troubleshooting

Common problems and how to fix them, from a computer that will not boot to a
package that will not install. If yours is not here, the system log usually says
what happened (see [Where the logs are](#where-the-logs-are)), and you can ask on the
[issue tracker](https://github.com/DevStarByte/ByteOS-OC/issues).

## Booting

### "unrecoverable error init:4: /lib/core/boot.lua"

OpenOS files are still on the disk, and the BIOS starts OpenOS's `init.lua` instead
of ByteOS's. This happens when ByteOS was copied onto a disk by hand. Erase the disk
and copy ByteOS again, or use the [installer](install.md), which erases the disk first.

### "ByteOS: no filesystem with /init.lua + /boot/kernel.lua found"

The BIOS found no disk with ByteOS on it. Check that the hard disk with ByteOS is in
the computer, and that the installation finished (the installer ends with
"Done. Take the OpenOS floppy out").

### The KERNEL PANIC screen

Instead of OpenComputers' own crash screen, ByteOS shows a red **KERNEL PANIC** title
with the error and where it happened. Press any key to reboot.

- If the panic comes right after `pacman -Syu` upgraded ByteOS, the panic screen puts
  the previous version back by itself and says *"The last update failed to boot; the
  previous version was restored."* After the reboot you are on the old version.
- Otherwise, note the first red line: it names the file and line that failed. If you
  changed a system file, boot the OpenOS floppy and put it back. Please report other
  panics on the [issue tracker](https://github.com/DevStarByte/ByteOS-OC/issues).

### The screen is only black and white

That is a Tier 1 graphics card or screen: they have no colours, so ByteOS uses a
clean black and white look. Tier 2 and up get the full colour theme.

## Memory and speed

### "not enough memory", or programs crash at random

The computer has too little RAM for what you are running. ByteOS itself needs about
190 KiB at the prompt, and `pacman` another 110–150 KiB while it works; see
[What you need](install.md#what-you-need).

- Put in more memory: Tier 2, or two sticks. `free` shows what you have.
- Big programs (the Hyprbyte desktop, `btop`) and many background jobs and services
  add up. `ps` shows what runs, `systemctl` which services are on.

### A program stops with "too long without yielding"

OpenComputers stops a program that runs for a few seconds without ever waiting, to
protect the server. ByteOS's own commands pause now and then; your own Lua code
should too. In a Lua loop that runs long, wait for a moment with `k.event.pull(0)`
now and then (in a shell script, `sleep 0.05`). Shell loops (`while`, `for`) pause by
themselves. ++ctrl+c++ stops a program while it waits.

## Logging in and passwords

### I forgot my password

If another user can use `sudo` (or you know root's password), set a new one:

```sh
alice@ByteOS ~> sudo passwd bob    # root may set anyone's password
```

### I forgot root's password and nobody can use sudo

ByteOS keeps passwords as salted hashes in `/etc/shadow`, and only root may read that
file. You can still get in from outside:

1. Insert the OpenOS floppy and boot it. OpenOS mounts the ByteOS disk under `/mnt`.
2. Edit `etc/shadow` on the ByteOS disk and replace root's line with
   `root:yournewpassword:::::::` (the password in plain text).
3. Take the floppy out and boot ByteOS. Log in as root with that password. ByteOS
   accepts a plain-text password once and replaces it with a hash right away.

!!! warning
    Anyone who can boot a floppy in your computer can do this. ByteOS's permissions
    protect users from each other, not against someone with access to the computer
    case (see [Users and permissions](../using/users.md)).

### "you cannot perform this operation unless you are root."

Installing, removing and upgrading packages needs root. Put `sudo` in front of the
command (your user must be in the `wheel` group), or log in as root.

### The keyboard types the wrong letters

ByteOS has no keyboard layout setting: OpenComputers passes on the characters your
Minecraft client sends. Set the layout in your game or operating system.

### Escape closes the screen

++escape++ always closes the Minecraft screen, so ByteOS programs never use it. In the
setup wizard, use **Shift+Q** (or ++backspace++ in lists) to go back.

## Packages

### "target not found: …"

`pacman` cannot find a package with that name. Search for the right one with
`pacman -Ss <part of the name>`. With *"(required by …)"* at the end, a package
needs something that is not in the repositories you have enabled in
`/etc/pacman.conf`.

### "no internet card"

The repositories in `/etc/pacman.conf` are on GitHub by default, so `pacman` needs an
internet card. For a computer without one, copy the `core/` and `extra/` folders of
the [packages branch](https://github.com/DevStarByte/ByteOS-OC/tree/packages) onto a
floppy and point the repositories at it:

```ini
[core]
Server = /mnt/1a2b3c4d/core
```

(`1a2b3c4d` stands for the first eight characters of the floppy's address; `ls /mnt`
shows it.) `pacman -Syu` then upgrades the packages but skips ByteOS itself, which
always comes from GitHub.

### Signature warnings and errors

The package lists ("databases") are signed. Checking a signature needs a **Tier 3
data card**. What happens without one depends on `SigLevel` in `/etc/pacman.conf`:

| SigLevel | Without a data card | With a data card |
|---|---|---|
| `Never` | not checked | not checked |
| `Optional` (default) | one warning, the lists are used | checked |
| `Required` | refused | checked |

Every downloaded package is checked against the SHA-256 in its list either way. *"the
signature is invalid; the database may have been tampered with"* means the list did
not match ByteOS's key: `pacman` keeps the previous list. Try again later; if it
persists, report it.

### A package was just released but pacman does not see it

GitHub caches files for a few minutes, and a new package also needs a minute to be
built after it is pushed. `pacman` asks GitHub for the newest version of the package
branch directly, so waiting a minute and running `sudo pacman -Sy` again is usually
all it takes.

### "not enough disk space"

The disk is full. `df` shows how much is left, `du -sh /var/cache` how much
downloaded packages take; `sudo pacman -Sc` empties that cache.

## Upgrades

### An upgrade went wrong

`pacman -Syu` backs up every file it replaces, so you can undo the last ByteOS
upgrade:

```sh
root@ByteOS ~# pacman --rollback
```

If the upgraded system does not boot at all, you do not need to do anything: the
kernel panic screen restores the previous version (see above).

### "… installed as … .new"

You changed a file in `/etc`, and the upgrade brought a new version of it. Your file
was kept, and the new one saved next to it as `<file>.new`. Compare them with
`diff /etc/pacman.conf /etc/pacman.conf.new` and keep what you want. Packages do the
same with their configuration files, saving the new one as `<file>.pacnew`.

## Where the logs are

Boot messages, logins, `sudo` and `su`, package changes, services and crashed programs
are written to the system log, `/var/log/messages`:

```sh
root@ByteOS ~# journalctl -n 20       # the last 20 lines
root@ByteOS ~# journalctl -u pacman   # only from one program or service
root@ByteOS ~# dmesg                  # everything since boot, with seconds since power-on
```

More in [Programs, services and logs](../using/processes.md).
