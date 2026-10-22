# Files, disks and links

This page covers where things live in ByteOS, the commands for working with
files, how extra disks and floppies show up, symbolic links, and packing files
into archives for a backup.

## Where things live

ByteOS uses the same layout as Linux. Everything starts at `/`, the hard disk
ByteOS booted from.

| Directory | What is in it |
|---|---|
| `/init.lua`, `/boot` | what starts ByteOS: the boot code and the kernel |
| `/sbin` | `init` (the first program) and the background services (`netd`, `timesyncd`, `crond`) |
| `/bin` | the commands of the base system (`ls`, `cp`, `pacman`, ...) |
| `/lib` | Lua libraries the system loads with `require` |
| `/etc` | settings: host name, users, time zone, `pacman.conf`, services |
| `/home/<user>` | each user's own files; root's home is `/home/root` |
| `/usr/bin`, `/usr/lib`, `/usr/share` | programs, libraries and data from [packages](../packages/pacman.md) |
| `/var` | what changes while ByteOS runs: the log (`/var/log/messages`), pacman's database, recorded permissions and links |
| `/tmp` | scratch space anyone may write to |
| `/mnt` | other disks, each in its own folder (see [Disks](#disks)) |

The system itself (`/init.lua`, `/boot`, `/sbin`, `/lib`, `/bin`) belongs to
the `byteos` package and is replaced when you run `sudo pacman -Syu`. Your files
in `/home` and your settings in `/etc` are kept.

## Working with files

Paths work as on Linux: `/etc/motd` is absolute, `notes.txt` is relative to the
directory you are in, `~` is your home, `..` the directory above. The
[shell](shell.md) completes paths with ++tab++.

```sh
alice@byteos ~> mkdir projects/lamp        # missing parents are made too
alice@byteos ~> cd projects/lamp
alice@byteos ~/p/lamp> edit main.lua       # full-screen editor: ^S save, ^Q quit
alice@byteos ~/p/lamp> cp main.lua backup.lua
alice@byteos ~/p/lamp> mv backup.lua old.lua
alice@byteos ~/p/lamp> rm old.lua
alice@byteos ~/p/lamp> less /etc/motd      # read a long file: q quits, /text searches
```

| Command | What it does |
|---|---|
| `ls [-a] [-l] [-t] [-r] [-1]` | list a directory: `-a` also hidden (dot) files, `-l` details, `-t` newest first, `-r` reversed |
| `cp [-r] SRC... DEST` | copy; `-r` copies directories with everything in them |
| `mv SRC... DEST` | move or rename; works across disks too |
| `rm PATH...` | remove files, **and directories with everything in them**, with or without `-r`, and without asking, so look twice |
| `mkdir DIR...` | create directories, missing parents included |
| `rmdir [-p] DIR...` | remove directories only if they are empty |
| `touch FILE...` | create empty files |
| <code>find [PATH] [-name PATTERN] [-type f&#124;d&#124;l] [-maxdepth N]</code> | list files below a directory |
| `stat FILE...` | size, type, owner, permissions and change time of a file |
| `edit FILE` | a full-screen editor with line numbers and Lua highlighting |
| `less FILE` | read text a screen at a time |
| `du [-s] [-h]`, `df` | how much space directories take, and how full each disk is |

Every command has a manual page: `man cp`, or the [command reference](../reference/commands.md).

### Reading `ls -l`

```text
alice@byteos ~> ls -l
drwxr-xr-x  alice users       -  Oct 21 14:03  projects/
-rw-r--r--  alice users    1.2K  Oct 21 14:10  notes.txt
lrwxrwxrwx  alice users       -  Oct 21 14:05  music -> /mnt/1a2b3c4d/music
```

The columns are: the type and permissions (`d` directory, `l` link, `-` file;
see [Users and permissions](users.md)), the owner, the group, the size, when the
file last changed, and the name. The date shows the time of day for files
changed in the last half year and the year for older ones. Without an internet
card ByteOS does not know the real time, so the year is always shown.

`ls -t` puts the newest files first; `ls -lt` is handy to see what just changed.

### Finding files

```sh
alice@byteos ~> find ~ -name '*.lua'          # quote the pattern, or the shell expands it first
alice@byteos ~> find /etc -type d -maxdepth 1  # only directories, one level down
alice@byteos ~> grep -n TODO ~/projects/lamp/main.lua
```

## Disks

Every disk in the computer besides the boot disk appears under `/mnt`, in a
folder named after the first eight characters of its address:
`/mnt/1a2b3c4d`. This also happens when you put a floppy in while ByteOS runs.
Take it out and the folder goes away.

```sh
alice@byteos ~> lsblk                  # every disk: address, label, size, where it is mounted
alice@byteos ~> df                     # how full each mounted disk is
alice@byteos ~> ls /mnt/1a2b3c4d
alice@byteos ~> cp notes.txt /mnt/1a2b3c4d/
```

`lsblk` also lists unmanaged drives (shown as `(unmanaged)`). ByteOS cannot use
those, because they have no file system.

Anyone may read and write the disks in `/mnt`, so a floppy works for every user.

### Mounting somewhere else

Root can mount a disk at any directory, naming it by the start of its address
or by its label, and unmount it again:

```sh
root@byteos ~# mount                          # what is mounted where
root@byteos ~# mount 1a2b /srv/data           # the disk whose address starts with 1a2b
root@byteos ~# umount /srv/data
```

A mount made this way lasts until the next reboot. `/` cannot be unmounted.

!!! tip "Which floppy is which?"
    A disk that has a label (set, for example, with OpenOS's `label` command)
    shows it in `lsblk`, and `mount` accepts the label instead of the address.

## Symbolic links

A symbolic link is a name that leads somewhere else. Opening the link opens
what it points to.

```sh
alice@byteos ~> ln -s /mnt/1a2b3c4d/music ~/music    # ~/music now leads to the disk
alice@byteos ~> cd ~/music                            # works like the real folder
alice@byteos ~> readlink ~/music                      # where it points: /mnt/1a2b3c4d/music
alice@byteos ~> readlink -f ~/music                   # the final path, every link followed
alice@byteos ~> ln -sf /etc/motd ~/music              # -f replaces an existing link
```

How the commands treat links:

- `cat`, `cd`, `edit`, programs and `cp` (without `-r`) use **what the link points to**.
- `rm` and `mv` act on the **link itself**. Removing a link never touches its target.
- `cp -r` and `tar` copy links as links.
- `find` and `du` do not walk through links into other directories; `find -type l` lists the links.
- `ls -l` shows `name -> target`, and `ls` colours links cyan.

A relative target counts from the link's directory: `ln -s ../lib/tool.lua
bin/tool.lua` makes `bin/tool.lua` lead to `lib/tool.lua`.

!!! note "Good to know"
    - OpenComputers disks cannot store links, so ByteOS keeps them in
      `/var/lib/links` on the boot disk. A link on a floppy only works while
      that floppy is mounted at the same place.
    - There are no hard links (`ln` without `-s`).
    - A link never gets around permissions: what it leads to is checked as if
      you had named it directly.

## Archives: tar and gzip

`tar` packs files, directories and links into one archive file, and `gzip`
makes files smaller. Both are [packages](../packages/pacman.md):

```sh
alice@byteos ~> sudo pacman -S tar gzip
```

```sh
alice@byteos ~> tar -cvf notes.tar notes/            # pack the folder notes/
alice@byteos ~> tar -tvf notes.tar                   # what is inside
alice@byteos ~> tar -xf notes.tar -C /tmp            # unpack into /tmp
alice@byteos ~> tar -xf notes.tar notes/todo.txt     # unpack only one file
alice@byteos ~> tar -czf notes.tar.gz notes/         # packed and compressed (needs gzip)
alice@byteos ~> tar -xf notes.tar.gz                 # .tar.gz is recognised by itself
alice@byteos ~> gzip big.log                         # big.log becomes big.log.gz
alice@byteos ~> zcat big.log.gz | grep error         # read it without unpacking
```

The archives use the standard formats, so they open on a PC too, and archives
made on a PC open in ByteOS. When unpacking, a leading `/` is taken off the
names and anything with `..` in its path is skipped, so an archive cannot write
outside the directory you unpack it in.

## Example: back up your home to a floppy

1. Put a floppy in the computer and find it:

    ```sh
    alice@byteos ~> lsblk
    ```

    Note the mount point, for example `/mnt/3f2a91c0`, and check with `df`
    that there is room (a floppy holds 512 KiB).

2. Pack your home folder onto it:

    ```sh
    alice@byteos ~> tar -czf /mnt/3f2a91c0/alice.tar.gz -C /home alice
    ```

    `-C /home alice` stores the files as `alice/...`, so the archive unpacks
    into a folder named after you.

    Without the tar and gzip packages, `cp -r ~ /mnt/3f2a91c0/alice` copies
    the folder as it is.

3. To restore it later, on this or another computer:

    ```sh
    alice@byteos ~> tar -tf /mnt/3f2a91c0/alice.tar.gz        # check what is inside
    alice@byteos ~> tar -xf /mnt/3f2a91c0/alice.tar.gz -C /home
    ```

To do this every night, see [scheduled jobs](processes.md).
