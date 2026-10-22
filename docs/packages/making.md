# Making packages

A package bundles a program (and anything it needs: libraries, config files, a
service) so that `pacman` can install, upgrade and remove it cleanly. This page shows
how to write one, build it inside ByteOS, and publish it, either in the official
repositories or in your own.

## What a package is made of

A package is built from a directory, much like Arch's `PKGBUILD` and `makepkg`:

```text
mytool/
├── PKGBUILD.lua          what the package is
├── mytool.install        optional hooks (run when installing, upgrading, removing)
└── files/                the files, laid out exactly as on the target disk
    ├── usr/bin/mytool.lua
    └── etc/mytool.conf
```

Everything under `files/` is installed at the same path: `files/usr/bin/mytool.lua`
becomes `/usr/bin/mytool.lua`. Programs go in `/usr/bin` (it is in `$PATH`), libraries
in `/usr/lib` (`require` finds them there), topic manual pages in
`/usr/share/man/<name>.txt`, other data in `/usr/share/<name>/`.

### PKGBUILD.lua

`PKGBUILD.lua` returns a table:

```lua
return {
  name       = "mytool",
  version    = "1.0.0",                      -- letters, digits and dots (no "-")
  rel        = 1,                            -- bump when only the packaging changes
  desc       = "my cool tool",
  url        = "https://github.com/me/mytool",
  depends    = { "lolcat", "figlet>=1.0" },  -- installed first, automatically
  optdepends = { "cowsay: talking output" }, -- suggested, not installed
  conflicts  = { "oldtool<2" },              -- cannot be installed together
  backup     = { "/etc/mytool.conf" },       -- config files: your edits survive
  groups     = { "fun" },                    -- pacman -S fun installs the whole group
  install    = "mytool.install",             -- the hook file, if there is one
}
```

| Field | Meaning |
|---|---|
| `name` | the package name: letters, digits and `- _ . +` |
| `version`, `rel` | the version is `version-rel`, e.g. `1.0.0-1`. Raise `version` for a new release, `rel` when only the packaging changed. |
| `desc` | one line, shown by `pacman -Ss` and `-Si` |
| `depends` | packages this one needs. A version may be given with `>=`, `<=`, `=`, `<` or `>`. Depend on `byteos>=1.16.0` if you need features of a recent ByteOS. |
| `optdepends` | `"name: what it adds"`; shown after installing and by `-Si`/`-Qi` |
| `conflicts` | packages that must not be installed at the same time (versions allowed) |
| `backup` | files under `/etc` the user may edit. On upgrade a changed copy is kept and the new one saved as `<file>.pacnew`; on removal the changed copy is kept as `<file>.pacsave`. Every listed file must be in `files/`. |
| `groups` | group names; `pacman -S <group>` installs all members |
| `install` | the name of the hook file next to `PKGBUILD.lua` |

A package with `depends` but no `files/` directory is a **meta package**: it installs
nothing of its own, only what it depends on.

`makepkg` checks the package while building: every `.lua` file under `files/` must
compile, and the hook file must load.

### The install hooks

The hook file defines any of four functions; all are optional:

```lua
-- mytool.install
function post_install(version) print("thanks for installing!") end
function post_upgrade(new, old) end
function pre_remove(version) end
function post_remove(version) end
```

They run as root inside pacman, with `fs`, `term`, `k` (the kernel), `shell` and
`require` at hand. If a hook fails, pacman warns and carries on.

## Building and installing it

Inside ByteOS:

```sh
root@byteos ~/mytool# makepkg
==> Making package: mytool 1.0.0-1
==> Finished making: mytool-1.0.0-1.bpk (412 bytes)
root@byteos ~/mytool# pacman -U mytool-1.0.0-1.bpk
```

`makepkg [dir]` builds the package in `dir` (default: where you are) and writes
`<name>-<version>.bpk` next to `PKGBUILD.lua`. `pacman -U` installs it; missing
dependencies come from the repositories.

## A complete example

A command that greets you in colour, with a manual page and a setting.

```text
greet/
├── PKGBUILD.lua
└── files/
    ├── usr/bin/greet.lua
    └── etc/greet.conf
```

`PKGBUILD.lua`:

```lua
return {
  name    = "greet",
  version = "1.0.0",
  rel     = 1,
  desc    = "greet someone in colour",
  depends = { "byteos>=1.16.0" },
  backup  = { "/etc/greet.conf" },
}
```

`files/etc/greet.conf`:

```text
# the word greet uses
word = Hello
```

`files/usr/bin/greet.lua`. The comment at the top **is** the manual page: `man greet`
shows it.

```lua
--[[
  greet [NAME] - greet someone in colour

    greet            greets you
    greet alice      greets alice

  The greeting word is set in /etc/greet.conf (word = Hello).
]]--
local name = (arg or {})[1] or _G.USER or "stranger"
local word = "Hello"
for line in (fs.readAll("/etc/greet.conf") or ""):gmatch("[^\n]+") do
  word = line:match("^%s*word%s*=%s*(.-)%s*$") or word
end
term.cwrite(term.theme.accent, word .. ", ")
term.write(name .. "!\n")
return 0
```

A program gets `arg` (its arguments), `term` (the screen: `write`, `cwrite` with a
colour, `read`), `fs` (files), `k` (the kernel), `shell` and `stdin`; it returns its exit
status. Look at the programs in `/bin` for more examples.

```sh
root@byteos ~# makepkg greet
root@byteos ~# pacman -U greet/greet-1.0.0-1.bpk
root@byteos ~# greet alice
Hello, alice!
```

## Packages with a service

A background program (a *service*) is shipped as a unit file in
`/usr/lib/systemd/system/<name>.service`:

```ini
[Unit]
Description=Remote Shell Daemon

[Service]
ExecStart=rshd
Restart=on-failure
```

`man systemd.service` lists every setting. Whether the service starts by itself is up to
the install hooks. A service that should always run (like `rshd` in the `rsh` package)
enables and starts itself:

```lua
function post_install()
  local systemd = require("systemd")
  systemd.enable("rshd")
  systemd.start("rshd")
end
function post_upgrade() require("systemd").restart("rshd") end
function pre_remove()
  local systemd = require("systemd")
  systemd.stop("rshd")
  systemd.disable("rshd")
end
```

A service that changes things in the world (like `reactorctl`) should rather print how to
turn it on, and leave that to the player.

The program behind a service must wait now and then with `k.event.pull` (as `sleep`
does): background programs only run while others wait.

## Publishing

### In the official repositories

The repositories are the
[`packages`](https://github.com/DevStarByte/ByteOS-OC/tree/packages) branch of the ByteOS
repository: the sources are in `pkgs/core/<name>/` and `pkgs/extra/<name>/`. Open a pull
request that adds your directory there. Once it is merged, GitHub builds every package,
signs the databases and commits them; a minute later `pacman -Sy` sees the new package.
To release a new version, raise `version` (or `rel`) in `PKGBUILD.lua`.

The [contributing guide](../reference/contributing.md) has the details, including how
packages are tested.

### Your own repository

A repository is just a directory with `<repo>.db` (the database) and the `.bpk` files it
lists, served from a web address or a disk. Build one on a PC (Lua 5.3 or newer) with
`tools/mkrepo.lua` from the ByteOS repository:

```sh
# on the PC: your packages in myrepo/pkgs/<repo>/<name>/
lua tools/mkrepo.lua myrepo
```

That writes `myrepo/<repo>/<name>-<version>.bpk` and `myrepo/<repo>/<repo>.db` for every
`<repo>` under `pkgs/`. Put the result somewhere ByteOS can reach (a web server, a public
GitHub repository's raw files, or a floppy) and add it to `/etc/pacman.conf`:

```ini
[mine]
Server = https://example.com/myrepo/mine
```

An unsigned repository is accepted with the default `SigLevel = Optional`. To sign your
database, make your own key pair once with `tools/repokey.sh` and build with
`lua tools/mkrepo.lua --key ~/.config/byteos/repo-key.pem myrepo`. ByteOS checks every
signature against one trusted key (`TrustedKey` in `pacman.conf`, the official one by
default), so a repository signed with a different key needs `SigLevel = Never` in its
section, or it is rejected on computers with a data card.

!!! note "The .bpk format"
    A `.bpk` is a simple archive: a `BPK1` line, then for each entry a header line
    (`<size> <flag> <name>`) and the raw bytes. The first entries are `.PKGINFO` and, if
    there are hooks, `.INSTALL`; then every file by its install path. Larger files are
    compressed (LZW) when that saves space. `lib/bpk.lua` reads and writes them.
