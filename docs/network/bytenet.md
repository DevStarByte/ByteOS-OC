# Between computers (ByteNet)

ByteOS computers with a **network card** find each other and talk over
*ByteNet*. They can send messages and files, run commands on each other, and
share folders. This page covers setting it up, the built-in commands, and the
`rsh` and `netfs` packages.

## Setting up

1. Put a **network card** in each computer. A wired card needs the computers
   connected with **cables** (through **relays** or switches for bigger
   networks). A **wireless network card** reaches other wireless cards within
   its range.
2. That's it. Every ByteOS computer runs the `netd` service, which listens on
   port 4400 and answers the others. A card put in later is picked up by itself.

Give each computer its own name, so you can tell them apart:

```sh
root@byteos ~# hostname box2       # the name others see (the prompt shows it too)
```

## The commands

```sh
alice@byteos ~> ip                         # this computer's card, its address, the host name
alice@byteos ~> netscan                    # every ByteOS computer on the network
alice@byteos ~> ping box2                  # is box2 there, and how fast does it answer?
alice@byteos ~> msg box2 dinner is ready   # shows up on box2's screen
alice@byteos ~> netcp notes.txt box2       # send a file to box2
```

| Command | What it does |
|---|---|
| `ip` | your network cards, wired or wireless (with the range), their addresses, whether netd listens |
| `netscan` | every computer that answers on ByteNet: name, address, ByteOS version, distance |
| `ping [-c N] HOST` | sends N pings (default 4) and shows each answer's time; ++ctrl+c++ stops early |
| `msg HOST TEXT` | a message on the other screen (or as a notification if it runs dunst) |
| `netcp FILE HOST` | sends a file; it arrives in `/tmp/incoming/` on the other computer |

### Naming a computer

Wherever a command wants a HOST, you can give:

- its **name**, as `netscan` shows it (`box2`);
- its full **address** (`5e1f0000-0000-0000-0000-000000000001`);
- or just the **first characters** of the address (`5e1f`), when no name matches.

### Receiving files

A file sent with `netcp` lands in `/tmp/incoming/` on the receiving computer,
named after the sender and the file (`/tmp/incoming/alice@box1-notes.txt`), and
that screen says so. Files are limited to **64 KiB**. Anything odd in the file
name is replaced, so a file cannot land outside `/tmp/incoming`.

!!! warning "Anyone on the network can send"
    OpenComputers networks have no login. Anyone whose computer is on the same
    network can send you messages and files. That is why files only ever land
    in `/tmp/incoming` and are size-limited. Don't connect computers you
    don't trust to the same network as important ones.

## Remote shell: rsh

The `rsh` package lets you run commands on another computer, as a user there.
Install it on **both** computers:

```sh
alice@byteos ~> sudo pacman -S rsh       # also starts the rshd service
```

```sh
alice@byteos ~> rsh box2 uptime          # run one command on box2 as alice
alice@byteos ~> rsh bob@box2 ls          # as bob (asks bob's password on box2)
alice@byteos ~> rsh alice@box2           # a prompt on box2 until you type exit
```

- `rsh` asks for the password of that user on the other computer. A command
  runs there as that user.
- Each command runs on its own and **cannot read the keyboard**, so
  interactive programs (editors, `less`) don't work through `rsh`. `cd` is
  remembered between commands at the prompt.
- A command still running after two minutes is stopped. After a wrong
  password, the other computer ignores you for a few seconds.

!!! warning
    The password crosses the network as plain text. Use `rsh` only on networks
    you trust.

## Shared folders: netfs

The `netfs` package lets one computer share folders that others use like a
disk. Install it on both:

```sh
alice@byteos ~> sudo pacman -S netfs     # also starts the netfsd service
```

**On the computer that shares**, list the folders in `/etc/netfs.conf`, one per
line: a name, the folder, and `ro` (others may only read) or `rw` (they may
also write and delete):

```text
# <name>  <directory>         ro|rw
public    /home/root/public   ro
drop      /srv/drop           rw
```

The file is read for every request, so changes count at once.

**On the other computers**, see what is shared and mount it:

```sh
alice@byteos ~> netfs shares box2                        # the folders box2 shares
root@byteos ~# netfs mount box2:public /mnt/pub          # use it as /mnt/pub
alice@byteos ~> ls /mnt/pub
alice@byteos ~> netfs                                    # what is mounted from where
root@byteos ~# netfs umount /mnt/pub
```

Mounting needs root. A mount lasts until the next reboot. A mounted share
works with every command, like a disk.

!!! warning "Shares are open to everyone on the network"
    Any computer on the network can use a share. Shares ignore ByteOS
    permissions: the sharing computer serves them as root, so share nothing
    secret. Paths cannot go above a shared folder (`..` stops at its top), and
    `/etc/shadow` is never served.

## More about the network

- ByteNet is ByteOS's own protocol on port 4400. Computers running OpenOS or
  other systems don't answer it.
- `netscan` and names only find computers that run `netd`, which is on by
  default (`systemctl status netd`).
- The [internet](internet.md) is a different card and a different page.
