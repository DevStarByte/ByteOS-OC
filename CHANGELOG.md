# Changelog

What changed in each ByteOS release. `sudo pacman -Syu` brings a
computer up to the newest one; `pacman --rollback` undoes the last
upgrade. The commit of each release has the full story.

## 1.17.1 — 2026-10-21

- `id -u`, `-g`, `-G` and `-n` (`id -un` prints your name).
- `ls -l` shows when each file last changed; `ls -t` sorts newest first,
  `ls -r` reverses the order. A link's line shows the link's own owner.
- `command NAME ARGS` runs the program or built-in even when a function
  or alias has that name.
- `trap '...' INT` runs on Ctrl+C, and the script goes on with its next
  command.
- `tar` is a package now (`sudo pacman -S tar`, in `extra`) instead of
  part of the base system; upgrading removes `/bin/tar`. It also takes
  member names: `tar -xf a.tar dir/file`.
- The `lua` prompt keeps its history in `~/.lua_history`.
- crond stays off until needed: `crontab` run by root offers to start it.

## 1.17.0 — 2026-10-21

- **Lua:** `lua` opens a prompt to try Lua line by line (expressions show
  their value, unfinished statements continue on the next line); `lua
  file.lua`, `lua -e CODE` and `lua -` run code without it.
- **Symbolic links:** `ln -s`, `readlink`, `realpath`. Links are kept in
  `/var/lib/links` (the disks cannot store them) and are followed
  everywhere; `rm` and `mv` act on the link, `find` and `du` do not walk
  through links, `cp -r` copies them as links, `ls -l` shows
  `name -> target`. What a link leads to is permission-checked as if
  named directly.
- **Archives:** `tar -c/-t/-x` with `-v -f -C`, in the ustar format, so
  archives open on a PC and the other way round.
- **Scheduled jobs:** `crontab -e/-l/-r` (jobs in `~/.crontab`, the
  system's in `/etc/crontab`) and the `crond` service that runs them,
  off by default: `systemctl enable --now crond`.
- **New commands:** `rmdir stat printf yes tac rev nl paste cmp base64
  uptime watch timeout time`.
- **Shell built-ins:** `eval`, `exec`, `shift`, `trap '...' EXIT`, `type`,
  `command -v`, `umask`; `test -L` checks for a link.
- **umask:** `umask 077` makes new files private; the default 022 changes
  nothing.
- `/etc/os-release` links to the GitHub repository and its issues.
- The tests run on GitHub for every push and pull request, with Lua 5.3
  and 5.4.

## 1.16.2 — 2026-10-06

- No release codename any more: boot line, setup, `/etc/issue`,
  neofetch and `uname -a` show just the version.
- `mv` no longer sometimes loses the permissions of a moved directory.

## 1.16.1 — 2026-10-06

- pacman is split into parts that load only when needed (a query needs
  36 KiB of code instead of 100) and lets go of its libraries when done.
- Pipes no longer copy their data at every stage.
- Fewer disk reads: the time zone, `chmod -R`/`chown -R`.

## 1.16.0 — 2026-10-06

- **Shell scripting:** fish's `if`/`else if`/`else`, `while`, `for`,
  `function`, `begin`, `break`, `continue`, `return`, `and`/`or`;
  `$(command)`; `test`/`[ ]`, `read`, `math`, `true`, `false`.
- **Text tools:** `sort uniq cut tr sed diff tee xargs seq basename
  dirname sha256sum mktemp`.
- **Permissions:** files have an owner, a group and a mode; `chmod`,
  `chown`, shown by `ls -l`.
- **pacman:** package groups, optional dependencies, `-Si`, meta
  packages.
- The setup wizard can add several users.

## 1.15.0 — 2026-10-05

- `~/.profile` runs once per login, after `~/.shrc` (`su` skips it,
  `su -` runs it).

## 1.14.2 — 2026-10-05

- The login no longer offers a session choice; Hyprbyte is started with
  `start-hyprbyte`.

## 1.14.1 — 2026-10-03

- No stale package databases from GitHub's cache: pacman fetches from
  the branch's newest commit. `-Syy` and `-Syyu` are accepted.

## 1.14.0 — 2026-10-03

- pacman remembers why a package is installed; `-Rs`/`-Rn`/`-Rns`
  remove unneeded dependencies; `-Qe -Qd -Qt -Qdt`; `-D --asdeps /
  --asexplicit`; `-` reads targets from a pipe.

## 1.13.3 — 2026-10-03

- `sudo` in a window stays root while its command waits.

## 1.13.2 — 2026-10-03

- The line being typed follows a resized window.

## 1.13.1 — 2026-10-03

- ByteNet messages show as notifications when dunst runs.

## 1.13.0 — 2026-10-03

- Terminals per process, so window managers can give each window its
  own; `$status`, jobs and Ctrl+C belong to their terminal.

## 1.12.1 — 2026-10-03

- Each background process keeps its own working directory.

## 1.12.0 — 2026-10-03

- **ByteNet:** computers with a network card find and talk to each
  other: the `netd` service, `ip`, `netscan`, `ping`, `msg`, `netcp`.

## 1.11.1 — 2026-10-03

- Less memory for the whole session: the setup wizard and the password
  code load only when needed (about 30 KiB less at the prompt).

## 1.11.0 — 2026-10-03

- Real time with 31 time zones and daylight saving time: the
  `timesyncd` service, `date`, `timedatectl`.
- A leaner setup wizard (no keyboard layout or locale questions).

## 1.10.0 — 2026-10-03

- `cp -r`, `mv` into directories and across disks, `fg`.

## 1.9.1 — 2026-10-03

- Install ByteOS over the internet from OpenOS with `install.lua`.

## 1.9.0 — 2026-10-03

- A test suite in the repository (`tools/test/run.lua`).
- `man` and `man -k`: a command's page is the comment at the top of its
  program.

## 1.8.0 — 2026-10-03

- Signed package databases (ECDSA, checked with a data card),
  versioned dependencies, `pacman -Ql/-Qo/-Sc`.

## 1.7.0 — 2026-10-03

- Background processes (`&`, `jobs`, `wait`, `ps`, `kill`), services
  (`systemctl`) and a system log (`journalctl`, `dmesg`, `logger`).

## 1.6.0 — 2026-10-03

- Everyday commands: `touch find less df du free date sleep which env
  hostname mount umount lsblk wget curl`; disks are mounted when they are
  put in.

## 1.5.0 — 2026-10-03

- Pipes, redirection, wildcards, shell scripts and Ctrl+C.

## 1.4.0 — 2026-10-03

- Hashed passwords, file permissions, user management (`passwd su
  useradd userdel usermod id groups`).

## 1.3.1 — 2026-10-03

- OpenOS leftovers removed; the installer speaks English.

## 1.3.0 — 2026-10-03

- ByteShell becomes fish-like: highlighting while typing,
  autosuggestions, history search, Tab completion, a history file.

## 1.2.0 — 2026-10-03

- Aliases, `source` and `~/.shrc`.

## 1.1.0 — 2026-10-03

- Upgrades through `pacman -Syu`, ByteBIOS as a package, the `.bpk`
  package format, `sudo`, `logout`; the version lives only in
  `/etc/os-release`.
