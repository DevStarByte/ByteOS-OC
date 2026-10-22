# First steps

A guided tour for your first ten minutes with ByteOS: logging in, finding help,
moving around, editing a file, adding a user and installing your first package.
It assumes you have [installed ByteOS](install.md) and set it up.

## Log in

After the boot messages (the `[ OK ]` lines) ByteOS shows its logo and asks for
your user name and password:

```text
ByteOS login: alice
Password:
```

The password is not shown while you type. Log in with the user you made in the
setup wizard, or as `root`. After the login you see the message of the day and a
short greeting.

## Read the prompt

```text
alice@ByteOS ~>
```

The prompt shows who you are (`alice`), the computer's name and the directory you
are in. `~` is your home directory, `/home/alice`. A normal user's prompt ends in
`>`, root's in `#` and is red, as a reminder that root may change anything. When a
command fails, the prompt shows its status, for example `[127]`.

While you type, ByteShell colours the line: a command it knows is blue, an unknown
one red, before you even press ++enter++. Grey text after the cursor is a
suggestion from your history; ++arrow-right++ takes it.

## Find help

```sh
alice@ByteOS ~> help            # every command and shell built-in
alice@ByteOS ~> man ls          # the manual page of one command
alice@ByteOS ~> man -k disk     # which pages mention "disk"
alice@ByteOS ~> man byteshell   # everything about the shell
```

A manual page opens in a pager: ++arrow-up++ / ++arrow-down++ scroll, ++space++
goes a page further, `/word` searches and `q` quits.
The same pages are in the [command reference](../reference/commands.md).

## Look around

```sh
alice@ByteOS ~> ls              # what is here
alice@ByteOS ~> ls -l /etc      # more detail: owner, size, date
alice@ByteOS ~> cd /etc         # go somewhere
alice@ByteOS /etc> cat motd     # print a file
alice@ByteOS /etc> cd           # back home (cd - goes back to the last directory)
alice@ByteOS ~> /usr/share      # typing a directory goes there too
```

Some time-savers:

- ++tab++ completes command names, files and directories. When there are several
  matches, it lists them.
- ++arrow-up++ brings back earlier commands. Type the start of one first
  (`pac`, then ++arrow-up++) to find only the ones that contain it.
- ++ctrl+c++ stops a running program; ++ctrl+l++ clears the screen.

The layout is the same as on Linux: programs in `/bin`, settings in `/etc`, homes
in `/home`, logs and package data in `/var`, what packages install in `/usr`.
Other disks appear under `/mnt`.

## Edit a file

`edit` is a full-screen text editor:

```sh
alice@ByteOS ~> edit notes.txt
```

| Key | Does |
|---|---|
| ++ctrl+s++ | save |
| ++ctrl+q++ | quit |
| ++ctrl+k++ / ++ctrl+u++ | cut the line / paste it |
| ++ctrl+g++ | go to a line number |

Lua files get syntax highlighting. Prefer something else? `nano` and `vim` are
[packages](../packages/list.md).

## Users and sudo

`root` may do anything. Everyone else may change only their own files (their home
directory, `/tmp` and `/mnt`). Users in the `wheel` group can run single commands as
root with `sudo`, giving their **own** password:

```sh
alice@ByteOS ~> sudo pacman -Syu
[sudo] password for alice:
```

`sudo` remembers the password for 5 minutes. To add another user (as root, or with
`sudo`):

```sh
root@ByteOS ~# useradd -m -G wheel bob   # -m: a home directory; -G wheel: may use sudo
root@ByteOS ~# passwd bob                # new accounts are locked until they get a password
alice@ByteOS ~> passwd                   # change your own password
```

More in [Users and permissions](../using/users.md).

## Install a package

`pacman` installs software from the ByteOS repositories through the internet card.
Installing needs root, so use `sudo`:

```sh
alice@ByteOS ~> pacman -Ss cow           # search
alice@ByteOS ~> sudo pacman -S cowsay    # install (it fetches the package lists itself)
alice@ByteOS ~> cowsay "I run Arch... ish."
alice@ByteOS ~> neofetch                 # the logo and your system
```

`pacman -Syu` upgrades all packages and ByteOS itself. Everything about it is on
[pacman](../packages/pacman.md); what there is to install is on the
[package list](../packages/list.md).

## Log out, reboot, shut down

```sh
alice@ByteOS ~> logout     # back to the login prompt (or Ctrl+D on an empty line)
alice@ByteOS ~> reboot     # restart the computer
alice@ByteOS ~> shutdown   # turn it off
```

Logging out also forgets a remembered `sudo` password.

## Where next

- [The shell](../using/shell.md): history, aliases, `~/.shrc` and every key.
- [Scripts](../using/scripting.md): pipes, redirection and shell scripts.
- [Files, disks and links](../using/files.md) and [Users and permissions](../using/users.md).
- [Programs, services and logs](../using/processes.md): background jobs, services, `cron`.
- [Between computers](../network/bytenet.md) and [the internet](../network/internet.md).
- [Hyprbyte](../desktop/hyprbyte.md): windows side by side.
