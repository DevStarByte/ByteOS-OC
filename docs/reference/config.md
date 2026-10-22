# Configuration files

Every file ByteOS and its packages read their settings from: what it is for, what
reads it, and what happens to it when you upgrade. The files are plain text; edit
them with `edit` (as root for files in `/etc`).

## How upgrades treat these files

`pacman -Syu` upgrades ByteOS and the packages, but it is careful with settings:

| Kind of file | On an upgrade |
|---|---|
| ByteOS's files in `/etc` (`pacman.conf`, `profile`, `motd`, `skel/`, `systemd/`, …) | Replaced only if you never changed them. If you did, yours stays and the new version is saved next to it as `<file>.new`. |
| `/etc/os-release`, `/etc/issue` | Always replaced: they describe the system. |
| `/etc/passwd`, `/etc/hostname` | Never touched. |
| Files ByteOS does not ship (`/etc/shadow`, `/etc/group`, `/etc/timezone`, `/etc/crontab`, …) | Never touched. |
| Homes (`/home`), `/var` | Never touched. |
| A package's configuration files (listed under `backup` in its PKGBUILD) | Kept if you changed them; the new version is saved as `<file>.pacnew`. `pacman -R` keeps a changed one as `<file>.pacsave` (`-Rn` deletes it). |

Compare a kept file with the new one using `diff`, for example
`diff /etc/pacman.conf /etc/pacman.conf.new`.

## The system: /etc

| File | What it is | Read by |
|---|---|---|
| `/etc/os-release` | The ByteOS version and links (`VERSION_ID`, `PRETTY_NAME`, …). The only place the version is kept. | boot, `uname`, `neofetch`, `pacman` |
| `/etc/issue` | The text above the login prompt. `\s`, `\r`, `\n` and `\l` stand for the system name, release, host name and terminal. | login |
| `/etc/motd` | The message of the day, shown after logging in. | login |
| `/etc/hostname` | The computer's name. Set it with `hostname NAME` as root. | boot, `hostname`, the prompt, ByteNet |
| `/etc/timezone` | The time zone, e.g. `Europe/Berlin`. Set it with `timedatectl set-timezone`. | the clock, `date`, `timedatectl` |
| `/etc/passwd` | The user accounts: `name:x:uid:gid:comment:home:shell`. | login, `sudo`, `su`, `id`, the kernel |
| `/etc/shadow` | Password hashes (`$sha256$…`). Only root may read it. Change passwords with `passwd`. | the kernel |
| `/etc/group` | Groups and their members: `name:x:gid:member,member`. Members of `wheel` may use `sudo`. | the kernel, `groups`, `id` |
| `/etc/profile` | Shell lines run at every login for everyone, before `~/.shrc`. Sets `PATH` and `EDITOR`. | ByteShell |
| `/etc/skel/` | The default `.shrc` and `.profile` every new user's home gets. | `useradd -m`, the setup wizard |
| `/etc/pacman.conf` | `pacman`'s settings and repositories. See `man pacman.conf` and [pacman](../packages/pacman.md). | `pacman` |
| `/etc/pacman.d/byteos.pub` | The public key the package lists are signed with. | `pacman` (with a Tier 3 data card) |
| `/etc/systemd/system/` | Your own services (`<name>.service`). Packages put theirs in `/usr/lib/systemd/system/`. See `man systemd.service`. | `systemctl`, boot |
| `/etc/systemd/enabled` | The services that start at boot, one per line. `systemctl enable` / `disable` change it. | boot |
| `/etc/crontab` | The system's scheduled jobs, with a user name before each command. See [Programs, services and logs](../using/processes.md). | `crond` |
| `/etc/.installed` | Marks a finished setup. Delete it and reboot to run the setup wizard again. | boot |
| `/etc/fstab` | Informational only: disks are mounted by the kernel (extra disks at `/mnt/<address>`). | nothing |
| `/etc/hosts` | Written by the setup wizard, in the Linux format. Nothing reads it yet. | nothing |

## Your home directory

| File | What it is |
|---|---|
| `~/.shrc` | Your aliases and variables, run at every login after `/etc/profile` (also by `su`). `source ~/.shrc` reloads it. |
| `~/.profile` | Run once per login, after `~/.shrc`. `su` skips it, `su -` runs it. |
| `~/.byteshell_history` | Your shell history (the newest 500 commands). `history clear` empties it. |
| `~/.lua_history` | What you typed at the `lua` prompt (the newest 200 entries). |
| `~/.crontab` | Your scheduled jobs. Change them with `crontab -e`. |
| `~/.config/` | Settings of desktop packages, see below. |

See [The shell](../using/shell.md) for what to put in `~/.shrc`.

## The system's state: /var

These are kept by ByteOS itself. You rarely need to edit them, but it helps to know
what they are.

| File | What it is |
|---|---|
| `/var/log/messages` | The system log. It is cut to its newer half when it grows past 32 KiB. Read it with `journalctl` and `dmesg`. |
| `/var/lib/perms` | Owners and modes set with `chmod` and `chown` (the disks cannot store them). |
| `/var/lib/links` | Symbolic links made with `ln -s` (the disks cannot store those either). |
| `/var/lib/pacman/local/` | One directory per installed package: its details and its files. |
| `/var/lib/pacman/sync/` | The downloaded package lists. |
| `/var/cache/pacman/` | Downloaded packages. `pacman -Sc` empties it. |
| `/var/lib/pacman/byteos/` | What the installer and upgrades installed, and the backup that `pacman --rollback` restores. |

## Packages

Packages that have settings install a default file; edit it as root.

| File | Package | What it is |
|---|---|---|
| `/etc/hyprbyte.conf`, then `~/.config/hyprbyte.conf` | `hyprbyte` | Gaps, the mod key, windows and programs to start (`exec-once = …`). Your file is read after the system one. See [Hyprbyte](../desktop/hyprbyte.md). |
| `~/.config/quickshell/shell.lua` (else `/etc/xdg/quickshell/shell.lua`) | `quickshell` | Your bars and widgets, in Lua. |
| `/etc/dunst/dunstrc`, then `~/.config/dunst/dunstrc` | `dunst` | Notification width, timeout and how many show at once. |
| `~/.config/hypr/hypridle.conf` (else `/etc/hypr/hypridle.conf`) | `hypridle` | What happens after a while without input. |
| `~/.config/hypr/hyprpaper.conf` (else `/etc/hypr/hyprpaper.conf`) | `hyprpaper` | The wallpaper. |
| `/etc/netfs.conf` | `netfs` | Folders this computer shares: <code>&lt;name&gt; &lt;directory&gt; ro&#124;rw</code> per line. |
| `/etc/pastebin.conf` | `pastebin` | Your pastebin.com developer key for `pastebin put` (`key = …`). |
| `/etc/reactorctl.conf` | `reactorctl` | When the automatic control stops and starts a reactor. See [Reactors](../modded/reactors.md). |
| `/etc/me-monitor.conf` | `me-monitor` | Minimum stock levels for the low-stock alerts. See [Applied Energistics 2](../modded/ae2.md). |
| `/etc/systemd/system/*.timer` | `timers` | Services started on a schedule (`man systemd.timer`). |

Where a line says *(else …)*, your own file replaces the system one completely; where
it says *then*, your file is read after it and only needs the settings you change.
