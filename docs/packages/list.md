# Package list

Every package in the ByteOS repositories, grouped by what it is for. Each one is
installed with `sudo pacman -S <name>`; inside ByteOS, `man <command>` shows a program's
full manual once it is installed. `pacman -Ss` lists the same packages with their
current versions.

`core` holds small everyday tools, `extra` the bigger programs. See [pacman](pacman.md)
for how installing and upgrading works.

## Everyday tools

### tar

`extra` · 1.1.0 · optional: `gzip`

Packs files, directories and symbolic links into one archive file, lists archives and
unpacks them. The archives are the standard ustar format, so `tar` on a PC opens them
and the other way round. Name single files after the archive to unpack only those. With
the `gzip` package, `-z` makes `.tar.gz` files, and `.tar.gz` files unpack without it.

```sh
alice@byteos ~> sudo pacman -S tar
alice@byteos ~> tar -cvf /mnt/1a2b3c4d/home.tar -C /home alice   # pack
alice@byteos ~> tar -tvf /mnt/1a2b3c4d/home.tar                  # look inside
alice@byteos ~> tar -xf home.tar alice/notes.txt                 # unpack one file
```

### gzip

`extra` · 1.0.0

`gzip`, `gunzip` and `zcat` for `.gz` files. Files packed here open on a PC and the other
way round. ByteOS packs a little less tightly than a PC's gzip. Damaged data is reported
and nothing is replaced. Without file names it packs or unpacks what comes through a pipe.

```sh
alice@byteos ~> sudo pacman -S gzip
alice@byteos ~> gzip notes.txt                  # notes.txt becomes notes.txt.gz
alice@byteos ~> zcat notes.txt.gz | grep todo   # read it without unpacking
alice@byteos ~> tar -czf backup.tar.gz ~/projects
```

### xxd

`core` · 1.0.0

Shows a file's bytes in hexadecimal, like vim's `xxd`, and turns such a dump back into a
file with `-r`. Handy for binary files, EEPROM images or packages.

```sh
alice@byteos ~> sudo pacman -S xxd
alice@byteos ~> xxd -l 64 /bin/ls.lua             # the first 64 bytes
alice@byteos ~> xxd -p data.bin > data.hex       # plain hex
alice@byteos ~> xxd -r -p data.hex > copy.bin    # and back
```

### tree

`core` · 1.0.0

A recursive, coloured listing of a directory and everything below it.

```sh
alice@byteos ~> sudo pacman -S tree
alice@byteos ~> tree /etc
```

### lua-json

`core` · 1.0.0

A JSON library for your Lua programs and the `lua` prompt: `json.decode` turns JSON text
into Lua tables, `json.encode` the other way (with `{ pretty = true }` for readable
output). Useful for the answers of web APIs downloaded with `wget`.

```sh
alice@byteos ~> sudo pacman -S lua-json
alice@byteos ~> lua -e 'local json = require("json"); print(json.encode({ a = 1, b = { 2, 3 } }))'
{"a":1,"b":[2,3]}
```

See [Lua](../using/lua.md) for writing Lua on ByteOS.

### uptime

`core` · 1.0.0

How long the computer has been running. ByteOS has had its own `uptime` command since
1.17.0, which comes first, so this package is no longer needed.

## The internet

These need an **internet card**. See [The internet](../network/internet.md) for
`wget`, `curl` and more.

### pastebin

`core` · 1.0.0

Gets programs from pastebin.com, runs them, and shares your own. A *code* is the part
after `pastebin.com/` (the whole address works too). Uploading needs your own pastebin
developer key in `/etc/pastebin.conf` (`key = ...`) or in the variable `PASTEBIN_KEY`;
`man pastebin` explains where to get one. Programs written for OpenOS may need libraries
ByteOS does not have.

```sh
alice@byteos ~> sudo pacman -S pastebin
alice@byteos ~> pastebin get x8Kq2Rt4 game.lua   # download a paste
alice@byteos ~> pastebin run x8Kq2Rt4            # download and run it
alice@byteos ~> pastebin put notes.txt           # upload (unlisted), prints the address
```

### gitget

`core` · 1.0.0 · needs `lua-json`

Downloads a GitHub repository, one folder of it, or a single file, from any public
repository. `-n` only lists what it would download; files over 256 KiB are skipped
(`-s` changes the limit) because OpenComputers disks are small. GitHub allows 60 lookups
an hour without signing in; each `gitget` uses two.

```sh
alice@byteos ~> sudo pacman -S gitget
alice@byteos ~> gitget DevStarByte/ByteOS-OC bin -o /tmp/b    # only the bin folder
alice@byteos ~> gitget someone/tools@dev util/x.lua           # one file from branch dev
alice@byteos ~> gitget -n someone/tools                       # just list it
```

### irc

`extra` · 1.0.0

A full-screen IRC chat client. It connects to irc.libera.chat (port 6667) unless you name
another server, as your user name unless you give `-n NICK`. A line without `/` goes to
the current channel. Commands: `/join`, `/part`, `/query`, `/msg`, `/me`, `/nick`,
`/names`, `/topic`, `/quote`, `/clear`, `/quit`. The connection is plain TCP, and the
server's OpenComputers config must allow the internet card to open TCP connections.

```sh
alice@byteos ~> sudo pacman -S irc
alice@byteos ~> irc -j byteos                       # join #byteos on irc.libera.chat
alice@byteos ~> irc -n alice irc.example.net '#help' # quote a channel written with #
```

!!! tip
    In the shell, an unquoted `#` starts a comment, so write channels as `-j byteos` or
    `'#byteos'` in quotes.

## System and monitoring

### btop

`extra` · 1.0.0

A full-screen monitor: memory and energy with their history, disks, the network card,
services and every process, updated every second. ++up++/++down++ pick a process, ++k++
stops it (yours, or any as root), ++q++ quits. `btop -1` draws one screen and ends.

```sh
alice@byteos ~> sudo pacman -S btop
alice@byteos ~> btop
```

### power

`extra` · 1.0.0

The computer's energy: how much is stored, how much it uses (or gains) per second, and
how long the rest lasts. `-w` keeps watching.

```sh
alice@byteos ~> sudo pacman -S power
alice@byteos ~> power -w
```

### lshw

`core` · 1.0.0

Every component in the computer with what OpenComputers reports about it (product,
vendor, capacity, clock, ...). Give a class to see only those. A good way to find out
which components another mod has added.

```sh
alice@byteos ~> sudo pacman -S lshw
alice@byteos ~> lshw -short          # one line per device
alice@byteos ~> lshw memory
```

### redstone

`core` · 1.0.0

Reads and sets redstone signals through a redstone card or a redstone I/O block, bundled
cables included. Setting outputs needs root. Sides are `bottom top back front right left`
(or 0-5).

```sh
alice@byteos ~> sudo pacman -S redstone
alice@byteos ~> redstone                    # every side: input and output
alice@byteos ~> redstone get top
alice@byteos ~> sudo redstone set front 15
alice@byteos ~> sudo redstone bundled back red 255
```

### timers

`core` · 1.0.0

Starts services on a schedule, like cron or systemd timers: a `<name>.timer` file next to
`<name>.service` in `/etc/systemd/system` says when (`OnCalendar=daily`, `14:30`,
`*:00/10`, `OnBootSec=2min`, `OnUnitActiveSec=1h`). `man systemd.timer` has the details.
For simple jobs, ByteOS's built-in `crontab` may be easier
(see [Programs, services and logs](../using/processes.md)).

```sh
alice@byteos ~> sudo pacman -S timers
alice@byteos ~> timers                       # every timer: next and last run
alice@byteos ~> sudo timers enable backup
```

## Between computers (ByteNet)

Both need a **network card** in every computer involved. See
[Between computers](../network/bytenet.md).

### rsh

`extra` · 1.0.0

A remote shell: runs a command on another ByteOS computer as you (or another user) and
prints what it printed, or gives you a prompt there until you type `exit`. The other
computer needs `rsh` too; installing it enables its `rshd` service. Passwords cross the
network as they are, so use it only on networks you trust.

```sh
alice@byteos ~> sudo pacman -S rsh
alice@byteos ~> rsh server uptime
alice@byteos ~> rsh alice@server
```

### netfs

`extra` · 1.0.0

Shared folders: use another computer's directories as if they were a disk. A computer
shares folders by listing them in `/etc/netfs.conf` as `ro` (read only) or `rw`; its
`netfsd` service answers the others, and changes count at once. Anyone on the network can
use a share, so share nothing secret. A mount lasts until the next reboot.

```sh
alice@byteos ~> sudo pacman -S netfs
root@byteos ~# echo "pub /home/root/public ro" >> /etc/netfs.conf   # share a folder
alice@byteos ~> netfs shares server
alice@byteos ~> sudo netfs mount server:pub /mnt/pub
```

## Editors

ByteOS comes with `edit`. These two are for people who know their namesakes.

### nano

`extra` · 2.0.0

A small editor in the style of GNU nano, with the shortcuts on the bottom two rows (^O
write, ^X exit, ^W search, ^K/^U cut and paste, ^T go to line). `-l` shows line numbers.

```sh
alice@byteos ~> sudo pacman -S nano
alice@byteos ~> nano -l notes.txt
```

### vim

`extra` · 1.0.0

A modal editor in the style of Vim: normal, insert and command mode, `hjkl`, `dd`, `yy`
and `p`, undo and redo, `/search`, counts (`3dd`), `:w`, `:q`, `:wq` and
`:%s/old/new/g` (plain text, not patterns). `man vim` lists everything it knows.

```sh
alice@byteos ~> sudo pacman -S vim
alice@byteos ~> vim notes.txt
```

## Fun and games

### play

`extra` · 1.0.0

Plays tunes on the computer's speaker, or on note blocks when there are any. Songs are
simple text files of notes; four public-domain songs come with it. See
[Holograms and music](../modded/holo-music.md) for the song format.

```sh
alice@byteos ~> sudo pacman -S play
alice@byteos ~> play -l                     # the songs it brings
alice@byteos ~> play ode-to-joy
alice@byteos ~> play -n "C4 E4 G4 C5*2"
```

### snake and 2048

`extra` · 1.0.0 each

Classic games. **snake**: steer with the arrow keys (or WASD), ++q++ quits. **2048**:
slide the tiles with the arrow keys, ++r++ restarts, ++q++ quits.

```sh
alice@byteos ~> sudo pacman -S snake 2048
alice@byteos ~> snake
```

### cowsay, lolcat, figlet, fortune

`core` (`figlet`: `extra`) · `cowsay` 0.2.0, the others 1.0.0

Text toys: `cowsay` puts your words in a cow's speech bubble, `lolcat` prints them in
rainbow colours, `figlet` in big block letters, and `fortune` shows a random quote.

```sh
alice@byteos ~> sudo pacman -S cowsay lolcat figlet fortune
alice@byteos ~> cowsay "I run Arch... ish."
alice@byteos ~> figlet ByteOS
alice@byteos ~> fortune
```

### sl, cmatrix, hello

`extra` (`hello`: `core`) · 1.0.0

`sl` sends a steam locomotive across the screen (the classic punishment for typing `sl`
instead of `ls`), `cmatrix` shows falling green "Matrix" rain until you press a key, and
`hello` greets you, the smallest possible example package.

## Desktop

These make up the Hyprbyte desktop; [Hyprbyte](../desktop/hyprbyte.md) shows how they
fit together.

| Package | Version | What it does |
|---|---|---|
| `hyprbyte` | 1.4.0 | a tiling window manager like Hyprland: windows side by side, nine workspaces, `hyprctl` |
| `quickshell` | 1.0.1 | bars and widgets for Hyprbyte, described in a Lua file |
| `dunst` | 1.0.0 | notification pop-ups, with history and do-not-disturb (`dunstctl`) |
| `libnotify` | 1.0.0 | `notify-send` and the library programs use to send notifications |
| `rofi` | 1.0.0 | a launcher (++alt+d++) and window switcher (++alt+w++) with fuzzy search |
| `hyprlock` | 1.0.0 | a lock screen with a big clock (++alt+l++) |
| `hypridle` | 1.0.0 | runs commands after a while without input, e.g. `hyprlock` |
| `hyprpaper` | 1.0.0 | wallpapers: text pictures and patterns behind the windows |

```sh
alice@byteos ~> sudo pacman -S hyprbyte quickshell dunst rofi hyprlock hypridle hyprpaper
```

## Modded Minecraft

Tools for other mods' machines, through OpenComputers. They have their own pages under
[Modded Minecraft](../modded/index.md).

| Package | Version | What it does |
|---|---|---|
| `reactorctl` | 1.0.0 | Big/Extreme Reactors: status, on/off, control rods, automatic control by the energy buffer ([Reactors](../modded/reactors.md)) |
| `me-monitor` | 1.0.0 | Applied Energistics 2: power, items, crafting CPUs, low-stock alerts ([AE2](../modded/ae2.md)) |
| `robot` | 1.0.0 | drives robots and drones from the shell or a step file ([Robots and drones](../modded/robots.md)) |
| `holo` | 1.0.0 | text and shapes on a hologram projector ([Holograms and music](../modded/holo-music.md)) |
