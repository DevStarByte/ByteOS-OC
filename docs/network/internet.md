# The internet

With an **internet card** a ByteOS computer can download files, keep its clock
on real time, install packages, fetch programs from pastebin and GitHub, and
chat on IRC. This page covers what each of these needs and how to use it.

## The internet card

Craft an internet card and put it in the computer. Nothing else needs setting
up. ByteOS uses it for:

- `wget` and `curl`, below;
- **the real time**: `timesyncd` asks the internet for the time at boot and every
  hour (see [time](../using/processes.md));
- **packages and upgrades**: `pacman` downloads from GitHub (see [pacman](../packages/pacman.md));
- the packages on this page.

!!! note "When the internet does not work"
    The server's OpenComputers configuration decides what the internet card may
    do. It can turn off web requests (HTTP) or direct connections (TCP, which
    IRC needs), and by default it blocks addresses on the server's own network
    (such as `127.0.0.1` or `192.168.x.x`). If downloads fail on a server, ask
    its admin. In single player, check `config/opencomputers/settings.conf`,
    section `internet`.

## Downloading: wget and curl

```sh
alice@byteos ~> wget https://example.com/tool.lua            # saved as tool.lua
alice@byteos ~> wget -O mytool.lua https://example.com/tool.lua
alice@byteos ~> wget -q -O - https://example.com/notes.txt   # print it instead (-q: no progress)
alice@byteos ~> curl example.com | head                      # print a page; pipes work
alice@byteos ~> curl -o page.html example.com                # save it
```

`wget` saves under the last part of the URL (or `index.html`), and `-O FILE`
chooses the name. `curl` prints what it fetched, and `-o FILE` saves it
instead. Both add `http://` when the URL has no scheme, and `https://` works
as well. When a `wget` download fails, it removes the half-written file.

## Programs from pastebin

The `pastebin` package (`sudo pacman -S pastebin`) gets code from
[pastebin.com](https://pastebin.com), the classic way OpenComputers players
share programs:

```sh
alice@byteos ~> pastebin get x8Kq2Rt4 game.lua      # download paste x8Kq2Rt4 as game.lua (-f overwrites)
alice@byteos ~> pastebin run x8Kq2Rt4 arg1 arg2     # download it and run it right away
alice@byteos ~> pastebin put game.lua               # upload (unlisted) and print the link
```

The code is the part after `pastebin.com/`; the whole address works too.

**Uploading** needs a pastebin developer key. Sign in on pastebin.com, open
<https://pastebin.com/doc_api>, copy "Your Unique Developer API Key", and put it in
`/etc/pastebin.conf`:

```text
key = 0123456789abcdef...
```

Or put `set PASTEBIN_KEY 0123...` in your `~/.shrc`. Every user can read
`/etc/pastebin.conf`, so on a shared computer the variable is the private choice.

!!! warning
    `pastebin run` runs whatever the paste contains, as you. Only run code you
    trust. Programs written for OpenOS may also need libraries ByteOS doesn't
    have.

## Repositories from GitHub: gitget

The `gitget` package (`sudo pacman -S gitget`) downloads a GitHub repository,
or just one folder or file of it:

```sh
alice@byteos ~> gitget DevStarByte/ByteOS-OC                  # the whole repository, into ./ByteOS-OC
alice@byteos ~> gitget DevStarByte/ByteOS-OC bin -o /tmp/b    # only its bin folder, into /tmp/b
alice@byteos ~> gitget someone/tools@dev util/x.lua           # one file, from the branch dev
alice@byteos ~> gitget -n someone/tools                       # only list what it would download
```

| Option | Meaning |
|---|---|
| `@BRANCH` | a branch other than the repository's default |
| `-o DIR` | where to put it (default: a new folder named after the repository or folder) |
| `-n` | list only, download nothing |
| `-s KiB` | skip files bigger than this (default 256) |
| `-f` | go on even if the disk looks too small; overwrite files |

GitHub answers 60 requests an hour without signing in. `gitget` uses two per
download; the files themselves don't count. OpenComputers disks are small, so
`gitget` warns before filling one up.

## Web APIs and JSON

Most web services answer in JSON. The `lua-json` package
(`sudo pacman -S lua-json`) gives scripts and the [`lua`](../using/lua.md)
prompt `json.decode` and `json.encode`:

```sh
alice@byteos ~> wget -q -O /tmp/repo.json https://api.github.com/repos/DevStarByte/ByteOS-OC
alice@byteos ~> lua -e 'local r = require("json").decode(fs.readAll("/tmp/repo.json")); print(r.full_name, r.default_branch)'
DevStarByte/ByteOS-OC	master
```

`json.encode(t, { pretty = true })` writes a table back as indented JSON. JSON
`null` becomes `json.null`.

## Chat: irc

The `irc` package (`sudo pacman -S irc`) is a full-screen IRC client. It
connects to `irc.libera.chat` on port 6667 by default, as your user name:

```sh
alice@byteos ~> irc -j byteos                              # Libera.Chat, join #byteos
alice@byteos ~> irc -n alice42 irc.libera.chat '#byteos'   # another nick; quote the #
alice@byteos ~> irc -p 6668 irc.example.net -j help        # another server and port
```

!!! tip "Quote channel names"
    In the shell, as in bash, an unquoted `#` starts a comment, so `irc
    #byteos` would join nothing. Use `-j byteos` or `'#byteos'`.

The screen shows the server, the current channel and your nick at the top,
the messages in the middle, and your line at the bottom. A line without `/`
goes to the current channel (or person):

| Command | What it does |
|---|---|
| `/join #chan` | join a channel, or switch to one you are in |
| `/part [#chan] [text]` | leave it |
| `/query NICK` | talk to one person; plain lines go to them |
| `/msg NICK TEXT` | send one private message |
| `/me TEXT` | an action (`* alice waves`) |
| `/nick NEW` | change your nick |
| `/names`, `/topic [TEXT]` | who is here; show or set the topic |
| `/quote LINE` | send a raw IRC line |
| `/clear` | empty the screen |
| `/quit [TEXT]` | leave (++ctrl+c++ and ++ctrl+d++ too) |

++up++ and ++down++ bring back what you typed, ++page-up++ and ++page-down++
scroll. Messages that mention your nick are yellow. If your nick is taken, a
`_` is added.

!!! note
    OpenComputers has no encryption for direct connections, so `irc` uses the
    plain port (6667, not 6697), and the server's OpenComputers config must
    allow TCP connections (see [the internet card](#the-internet-card)).
