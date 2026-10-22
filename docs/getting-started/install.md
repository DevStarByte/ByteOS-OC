# Installing

This page takes you from an empty computer case to a ByteOS login prompt: what to
build, how the installer works, and what the setup wizard asks on the first boot.
It also covers the other ways to install, the ByteBIOS boot loader, and keeping
ByteOS up to date.

## What you need

| Part | Notes |
|---|---|
| Computer case | Any tier. |
| CPU | Any tier. |
| Memory (RAM) | **Tier 2 is safe**, one Tier 1.5 stick should just do. See below. |
| EEPROM | The Lua BIOS that comes with OpenComputers works; ByteBIOS can replace it later. |
| Hard disk drive | A managed (normal) hard disk. The installer erases it. |
| Screen, keyboard, graphics card | Any tier. ByteOS adapts to every screen from 50×16 up to 160×50. |
| Internet card | For installing over the internet and for `pacman`. |
| OpenOS floppy | Craft a floppy disk together with the OpenComputers manual, or take it from the creative tab. The installer runs under OpenOS. |
| Tier 3 data card (optional) | Lets `pacman` check the signatures of the package lists. |

!!! note "How much memory?"
    Measured with 64-bit Lua, ByteOS keeps about 190 KiB of code loaded at the
    prompt, and `pacman` needs another 110–150 KiB while it runs. A Minecraft
    server running 64-bit Java counts memory with a factor (`ramScaleFor64Bit`,
    1.8 by default), so one Tier 1.5 stick gives about 460 KiB there. Two
    sticks, or Tier 2, leave comfortable room for bigger programs and the
    Hyprbyte desktop.

On a Tier 1 graphics card and screen you get a clean black and white look; from
Tier 2 up, ByteOS loads its own 16-colour palette so Tier 2 and Tier 3 look the same.

## Install over the internet

This is the easiest way. Everything happens inside the game.

1. Put the blank hard disk and the internet card in the computer, insert the
   OpenOS floppy and turn the computer on. It boots OpenOS.
2. In the OpenOS shell, type these two lines:

    ```sh
    wget -f https://raw.githubusercontent.com/DevStarByte/ByteOS-OC/master/install.lua /tmp/install.lua
    /tmp/install.lua
    ```

3. Answer the installer's questions. Pressing ++enter++ takes the default shown
   in brackets, except for erasing the disk, which you have to confirm with `yes`:

    | The installer asks | What to answer |
    |---|---|
    | **Source** — `1) the internet` or `2) a disk with the ByteOS files` | `1`. It is the default when the computer has an internet card. |
    | **Which one is the target** | The number of your hard disk. The list only shows disks that can take ByteOS: writable ones, not the floppy OpenOS runs from and not the temporary disk. With just one disk, ++enter++ picks it. |
    | **Continue?** (everything on the disk will be ERASED) | `yes`. Anything else stops here and nothing changes. |
    | **Flash ByteBIOS onto the EEPROM?** | ++enter++ (yes). ByteOS also boots with the Lua BIOS, so `no` is fine too. |
    | **Reboot now?** | ++enter++ (yes). |

4. Take the OpenOS floppy out. ByteOS boots, and the setup wizard starts.

What the installer does along the way:

- It asks GitHub for the newest ByteOS and downloads only the system itself:
  `/init.lua`, `/boot`, `/sbin`, `/lib`, `/bin`, `/etc`, `/home`, `/var` and `/usr`.
- It refuses a disk that is too small (it needs the size of ByteOS plus 64 KiB).
- It labels the disk `ByteOS` and remembers exactly which files it installed,
  so a later `sudo pacman -Syu` only fetches what changed.
- If you flash ByteBIOS, your old BIOS is saved first, and the EEPROM is pointed
  at the new disk. If the EEPROM is read-only, it keeps its BIOS.

!!! warning
    The installer erases **everything** on the target disk. Make sure you picked
    the right number: the list shows each disk's address, label and free space.

## The first start: the setup wizard

On the very first boot ByteOS notices that `/etc/.installed` is missing and runs
a full-screen setup wizard. After a welcome screen you get a summary:

```text
 ByteOS Setup                                            Settings
           ┌──────── Installation summary ────────┐
           │ ✓ Hostname                    ByteOS │
           │ ✓ Timezone                       UTC │
           │ • Root password             required │
           │ ✓ User accounts            root only │
           │ ──────────────────────────────────── │
           │   Install ByteOS                     │
           │   Abort and reboot                   │
           └──────────────────────────────────────┘
 ↑↓ move  Enter change  Shift+Q abort
```

Move with ++arrow-up++ / ++arrow-down++ (or press `1`–`9`) and press ++enter++ to
change an entry:

Hostname
:   The computer's name, shown in the prompt and to other computers on the
    network. Letters, digits, `-` and `_`. The default is `ByteOS`.

Timezone
:   Pick yours from the list. It applies to the real time, which ByteOS fetches
    from the internet (see [Programs, services and logs](../using/processes.md)).

Root password
:   Required. `root` is the administrator account.

User accounts
:   Opens a list where you add as many users as you like. Each gets a name, a
    password and the choice whether they may use `sudo` (that adds them to the
    `wheel` group). Pick a user again to change their password, their `sudo`, or
    to remove them. A home directory `/home/<name>` is created for each, with
    the default `.shrc` and `.profile`.

When everything is set, choose **Install ByteOS** and confirm. The wizard writes
`/etc/hostname`, `/etc/timezone`, `/etc/passwd`, `/etc/shadow`, `/etc/group` and
the `/etc/.installed` marker, so it never runs again. From then on every boot goes
straight to the login prompt.

!!! tip "Going back"
    ++escape++ closes the Minecraft screen instead of reaching the computer, so in
    the wizard **Shift+Q** (or ++backspace++ in lists) means *back*. On the summary,
    Shift+Q offers to abort and reboot without installing.

!!! tip "Redo the setup"
    Delete `/etc/.installed` as root (`rm /etc/.installed`) and reboot. The wizard
    runs again and writes new account files.

## Other ways to install

### From a disk instead of the internet

Without an internet card, put the ByteOS files on a floppy (or any disk), boot
OpenOS, run `install.lua` from that disk and choose `2` (a disk) as the source.
The installer finds the disk that holds ByteOS by itself; if none has it at the
top level, it asks which disk and which folder on it to use.

### By hand

Copy `init.lua`, `boot/`, `sbin/`, `lib/`, `bin/`, `etc/`, `home/`, `var/` and
`usr/` from the repository onto the hard disk. Outside Minecraft the disk is a
folder: `saves/<world>/opencomputers/<disk-uuid>/`. ByteOS also starts with the
stock Lua BIOS.

A system copied by hand has no record of what was installed, so the first
`pacman -Syu` downloads every file once. After that, upgrades only fetch what changed.

!!! warning "unrecoverable error init:4: /lib/core/boot.lua"
    If you see this after copying ByteOS by hand, OpenOS files are still on the
    disk and the BIOS starts them instead. Erase the disk first, or use the
    installer, which does.

## ByteBIOS, the boot loader

ByteBIOS is a small BIOS for the EEPROM that finds and boots `/init.lua`. ByteOS
boots fine with the stock Lua BIOS too, so this is optional. Inside ByteOS:

```sh
root@byteos ~# pacman -S bytebios   # flash ByteBIOS (the old BIOS is saved)
root@byteos ~# pacman -R bytebios   # put the old BIOS back
```

Before flashing, `pacman` compiles ByteBIOS and checks that it fits; afterwards it
reads the EEPROM back and puts the old code back if anything does not match. Once
ByteBIOS is on the EEPROM, `pacman -Syu` keeps it current. A different BIOS is never
replaced unless you ask for it.

If an EEPROM ever ends up unbootable, craft a fresh Lua BIOS (an EEPROM together
with the manual) and swap it in.

## Keeping ByteOS up to date

ByteOS updates itself through `pacman`, like the packages:

```sh
root@byteos ~# pacman -Syu         # upgrade the packages and ByteOS itself
root@byteos ~# pacman --rollback   # undo the last ByteOS upgrade
```

An upgrade only replaces system files (`/init.lua`, `/boot`, `/sbin`, `/lib`,
`/bin`, `/usr/share/man`, and `/etc/os-release` and `/etc/issue`). Your home
directories, `/var`, the user accounts and installed packages are never touched.
Files in `/etc` that you changed are kept; the new version is saved next to them as
`<file>.new`.

Everything that is replaced is backed up first. If the upgraded system fails to
boot, the kernel panic screen restores the previous version by itself and says so;
press a key to reboot into it. More in [pacman](../packages/pacman.md).

## Next steps

- [First steps](first-steps.md): log in and find your way around.
- [Troubleshooting](troubleshooting.md): when something does not work.
