# Users and permissions

ByteOS has user accounts like Linux: everyone has a name, a password and a home
folder, and only root may change the system. This page covers managing
accounts, `sudo` and `su`, and who may read and write which files.

## Accounts

The setup wizard on the first boot asks for root's password and lets you add
users. Each account has:

- a **name** and a **user id** (root is 0, the first user 1000);
- a **home** folder, `/home/<name>` (root's is `/home/root`);
- a **primary group** (`users` for normal accounts) and possibly more groups.
  Members of the group `wheel` may use `sudo`.

```sh
alice@byteos ~> whoami                 # alice
alice@byteos ~> id                     # uid=1000(alice) gid=100(users) groups=100(users),10(wheel)
alice@byteos ~> id -un                 # just the name, for scripts
alice@byteos ~> groups                 # users wheel
```

### Adding and removing users

Only root can manage accounts, so a user in `wheel` puts `sudo` in front:

```sh
alice@byteos ~> sudo useradd -m -G wheel bob   # -m: a home made from /etc/skel; -G wheel: may sudo
alice@byteos ~> sudo passwd bob                # a new account is locked until it has a password
alice@byteos ~> sudo usermod -aG wheel carol   # add carol to wheel; -rG removes from groups
alice@byteos ~> sudo userdel -r bob            # delete bob; -r also removes his home
```

`useradd -s SHELL` sets a different login shell (the default is `/bin/sh`).
New homes get a copy of `/etc/skel`, which holds a starting `.shrc` (aliases
such as `ll`) and a commented `.profile`.

### Passwords

```sh
alice@byteos ~> passwd                 # change your own: asks for the current one first
root@byteos ~# passwd alice            # root sets anyone's, without the old one
```

Passwords are stored as salted SHA-256 hashes (`$sha256$512$salt$hash`) in
`/etc/shadow`, which only root can read. A plain-text password from a very old
ByteOS is turned into a hash the next time that user logs in.

### The account files

| File | What it holds |
|---|---|
| `/etc/passwd` | one line per user: `name:x:uid:gid:comment:home:shell` |
| `/etc/shadow` | the password hashes (root only) |
| `/etc/group` | one line per group: `name:x:gid:member,member` |

The commands above edit these files for you. If you edit them by hand, ByteOS
notices and reads them again.

## Running things as root: sudo and su

`sudo` runs one command as root. It asks for **your own** password and
remembers it for 5 minutes. Only members of `wheel` may use it, and three wrong
passwords end the attempt. Attempts are written to the system log.

```sh
alice@byteos ~> sudo pacman -Syu
[sudo] password for alice:
alice@byteos ~> sudo -k                # forget the remembered password now
```

`su` starts a whole shell as another user (root by default), asking for **that
user's** password. Root needs none. `exit` brings you back.

```sh
alice@byteos ~> su                     # a root shell
alice@byteos ~> su bob                 # a shell as bob, with bob's ~/.shrc
alice@byteos ~> su - bob               # the same, as a full login (also runs bob's ~/.profile)
```

### Logging out

`logout` or ++ctrl+d++ on an empty line goes back to the login prompt, so
another user can log in. It also forgets a remembered `sudo` password.

The kernel keeps track of who you are, not the `$USER` variable: `USER`,
`HOME` and `LOGNAME` are read-only in the shell, and `whoami` asks the kernel.

## Who may read and write what

Every file has an **owner**, a **group** and a **mode**. The mode says what
the owner, the group and everyone else may do: **r** read, **w** write,
**x** run (for a directory: enter it). `ls -l` shows it:

```text
-rw-r--r--  alice users     1.2K  Oct 21 14:10  notes.txt
 ^^^ owner (alice): read, write
    ^^^ group (users): read
       ^^^ others: read
```

### The defaults

OpenComputers disks cannot store owners or modes, so ByteOS gives every file
one by where it is:

| Where | Owner and group | Mode |
|---|---|---|
| `/home/<user>/...` | that user, group `users` | `rw-r--r--` (folders `rwxr-xr-x`) |
| `/tmp`, `/mnt` (other disks) | root | `rw-rw-rw-` (folders `rwxrwxrwx`): everyone may write |
| `/etc/shadow` | root | `rw-------` |
| everything else | root | `rw-r--r--` (folders `rwxr-xr-x`) |

So a normal user may write only in their home, in `/tmp` and on other disks,
and can read most of the system but not `/etc/shadow`. Root may do anything.

```sh
alice@byteos ~> rm /bin/ls.lua
rm: cannot remove '/bin/ls.lua': permission denied
```

### Changing permissions: chmod and chown

`chmod` changes the mode, either as octal digits or with letters. Only root and
the file's owner may do it. `chown` changes the owner and group, and only root
may.

```sh
alice@byteos ~> chmod 600 notes.txt            # only alice may read and write it
alice@byteos ~> chmod go-rx ~/private          # nobody else gets into the folder
alice@byteos ~> chmod u+x,go=r tool.lua        # letters: u owner, g group, o others, a all
root@byteos ~# mkdir /srv/team
root@byteos ~# chown alice:wheel /srv/team     # owner alice, group wheel
root@byteos ~# chmod 775 /srv/team             # alice and the wheel group may write there
root@byteos ~# chown -R alice /srv/team        # -R: everything inside too (chmod -R as well)
```

Changes are kept in `/var/lib/perms` and follow files through `mv` and `rm`.
Only files that were changed are listed there; all others keep the defaults.

What is checked:

- **r** and **w** on files and folders.
- **x** on a folder in `/var/lib/perms`, which must allow you through to reach what is inside.
- **x** on a file is shown but not enforced. Any readable program can be run.

### New files: umask

The `umask` decides what new files and folders get. The default, `022`, gives
the usual `644` and `755`. To keep everything new private, put this in your
`~/.shrc`:

```sh
umask 077          # new files rw-------, new folders rwx------
```

`umask` on its own shows the current value. It lasts until you log out, which is
why it belongs in `~/.shrc`.

## What the protections are for

The permissions keep users from breaking the system by accident and from
reading or changing each other's files. **They are not a sandbox.** In
OpenComputers every program can talk to the hardware directly through the
`component` API, so a deliberately written program can get around them. Only
give accounts to players you trust with the computer.
