# ByteOS Package List

This is the `packages` branch of ByteOS-OC: the pacman repositories only,
kept apart from the OS on `master` so cloning the OS doesn't drag every
package along. pacman downloads straight from here through the internet card
(see `/etc/pacman.conf`). For an offline computer, copy `core/` and `extra/`
onto a floppy and point `Server` at it.

Install with `pacman -S <name>`.
After a fresh install, run `pacman -Sy` once to refresh the database.

## core/

Small, everyday tools. Always enabled.

| Package | Version | Description |
|---------|---------|-------------|
| [hello](core/hello-1.0.0.pkg)     | 1.0.0 | A friendly greeter package. |
| [cowsay](core/cowsay-0.2.0.pkg)   | 0.2.0 | ASCII-art talking cow. `cowsay "moo"` |
| [lolcat](core/lolcat-1.0.0.pkg)   | 1.0.0 | Cycle terminal colours across text. `lolcat hello` |
| [fortune](core/fortune-1.0.0.pkg) | 1.0.0 | Random pithy programmer quotes (ships its own data file). |
| [tree](core/tree-1.0.0.pkg)       | 1.0.0 | Recursive coloured directory listing. `tree /etc` |
| [uptime](core/uptime-1.0.0.pkg)   | 1.0.0 | Print how long the system has been running. |
| [sudo](core/sudo-1.0.0.pkg)       | 1.0.0 | Run a command as root. Checks `wheel` in `/etc/group` and the password in `/etc/shadow`. |

## extra/

Bigger or more demo-y packages. Enabled by default in `/etc/pacman.conf`.

| Package | Version | Description |
|---------|---------|-------------|
| [vim](extra/vim-0.1.0.pkg)         | 0.1.0 | The "use edit instead :q!" joke stub. |
| [figlet](extra/figlet-1.0.0.pkg)   | 1.0.0 | ASCII-art big-letters renderer with a bundled font. Ships **compressed** (`.pkg.z`, 5.9 KB → 3.3 KB) — pacman picks the compressed copy automatically. |
| [sl](extra/sl-1.0.0.pkg)           | 1.0.0 | Steam Locomotive — the classic punishment for typing `sl` instead of `ls`. |
| [cmatrix](extra/cmatrix-1.0.0.pkg) | 1.0.0 | Falling green Matrix rain. Press any key to quit. |
| [nano](extra/nano-1.0.0.pkg)       | 1.0.0 | Tiny line-buffer editor. `:w` save, `:q` quit, `:wq`, `:d` drop last line. |
| [snake](extra/snake-1.0.0.pkg)     | 1.0.0 | **Game.** Classic snake. Arrow keys (or WASD) to steer, `q` to quit. |
| [2048](extra/2048-1.0.0.pkg)       | 1.0.0 | **Game.** Slide-the-tiles puzzle. Arrows to move, `r` restart, `q` quit. |

## Quick demo run

```sh
pacman -Sy
pacman -Ss                        # browse everything
pacman -S lolcat fortune tree     # core picks
pacman -S sl cmatrix figlet       # extra fun
sudo pacman -S nano               # via the new sudo
fortune
tree /etc
sl
cmatrix
figlet ByteOS
```

## Package format cheatsheet

* `<name>-<version>.pkg` — plain Lua table: `return { files = { [path] = "…" }, post_install = function() … end }`
* `<name>-<version>.pkg.z` — same shape, but every file is LZW + base64. Marker: `format = "lzw1"`. Use `mkpkg foo.pkg` to compress, `mkpkg -d foo.pkg.z` to decompress.
* `<repo>/repo.db` (here: `core/` and `extra/`) — one line per package: `<name> <version> <description>`.

Add a new package by dropping its `.pkg` (or `.pkg.z`) into a repo folder and appending a line to that folder's `repo.db`.
