# ByteOS Package List

This is the `packages` branch of ByteOS-OC: the pacman repositories only,
kept apart from the OS on `master` so cloning the OS doesn't drag every
package along. pacman downloads straight from here through the internet card
(see `/etc/pacman.conf`). For an offline computer, copy `core/` and `extra/`
onto a floppy and point `Server` at it.

Install with `pacman -S <name>`; `pacman -S` syncs the databases itself
the first time.

## core/

Small, everyday tools. Always enabled.

| Package | Version | Description |
|---------|---------|-------------|
| [hello](pkgs/core/hello)     | 1.0.0 | A friendly greeter package. |
| [cowsay](pkgs/core/cowsay)   | 0.2.0 | ASCII-art talking cow. `cowsay "moo"` |
| [lolcat](pkgs/core/lolcat)   | 1.0.0 | Cycle terminal colours across text. `lolcat hello` |
| [fortune](pkgs/core/fortune) | 1.0.0 | Random pithy programmer quotes (ships its own data file). |
| [tree](pkgs/core/tree)       | 1.0.0 | Recursive coloured directory listing. `tree /etc` |
| [uptime](pkgs/core/uptime)   | 1.0.0 | Print how long the system has been running. |
| [lshw](pkgs/core/lshw)       | 1.0.0 | Every component with its details. `lshw -short`, `lshw memory` |
| [redstone](pkgs/core/redstone) | 1.0.0 | Read and set redstone signals and bundled cables. `redstone set top 15` |
| [timers](pkgs/core/timers)   | 1.0.0 | Start services on a schedule, like cron: `.timer` units, `timers`, `man systemd.timer`. |

## extra/

Bigger or more demo-y packages. Enabled by default in `/etc/pacman.conf`.

| Package | Version | Description |
|---------|---------|-------------|
| [vim](pkgs/extra/vim)         | 0.1.0 | The "use edit instead :q!" joke stub. |
| [figlet](pkgs/extra/figlet)   | 1.0.0 | ASCII-art big-letters renderer with a bundled font. Ships **compressed** (`.pkg.z`, 5.9 KB → 3.3 KB) — pacman picks the compressed copy automatically. |
| [sl](pkgs/extra/sl)           | 1.0.0 | Steam Locomotive — the classic punishment for typing `sl` instead of `ls`. |
| [cmatrix](pkgs/extra/cmatrix) | 1.0.0 | Falling green Matrix rain. Press any key to quit. |
| [nano](pkgs/extra/nano)       | 1.0.0 | Tiny line-buffer editor. `:w` save, `:q` quit, `:wq`, `:d` drop last line. |
| [snake](pkgs/extra/snake)     | 1.0.0 | **Game.** Classic snake. Arrow keys (or WASD) to steer, `q` to quit. |
| [2048](pkgs/extra/2048)       | 1.0.0 | **Game.** Slide-the-tiles puzzle. Arrows to move, `r` restart, `q` quit. |
| [btop](pkgs/extra/btop)       | 1.0.0 | Full-screen monitor: memory, energy, disks, network, services, processes (`k` stops one). |
| [power](pkgs/extra/power)     | 1.0.0 | Energy stored, use per second, time left. `power -w` keeps watching. |
| [rsh](pkgs/extra/rsh)         | 1.0.0 | Remote shell over ByteNet: `rsh alice@box2 uptime`, or a prompt there. |
| [netfs](pkgs/extra/netfs)     | 1.0.0 | Shared folders over ByteNet: share in `/etc/netfs.conf`, `netfs mount box2:pub /mnt/pub`. |
| [hyprbyte](pkgs/extra/hyprbyte) | 1.3.1 | Tiling window manager like Hyprland: terminals side by side, 9 workspaces, `hyprctl`; no bar of its own (quickshell draws one). Alt+Enter opens a terminal; also a login session (F2). Layers, key grabs and `bind =` for the ecosystem below (1.2). |
| [quickshell](pkgs/extra/quickshell) | 1.0.1 | Your own bars and widgets for Hyprbyte, from `~/.config/quickshell/shell.lua` (reloads on save). `exec-once = quickshell` |
| [libnotify](pkgs/extra/libnotify) | 1.0.0 | `notify-send` and the notification library. |
| [dunst](pkgs/extra/dunst)     | 1.0.0 | Notification pop-ups for Hyprbyte; `dunstctl` history and do-not-disturb. `exec-once = dunst` |
| [rofi](pkgs/extra/rofi)       | 1.0.0 | Launcher with fuzzy search (Alt+D) and window switcher (Alt+W). |
| [hyprlock](pkgs/extra/hyprlock) | 1.0.0 | Lock screen with a big clock (Alt+L). |
| [hypridle](pkgs/extra/hypridle) | 1.0.0 | Run commands when idle, e.g. lock after 5 minutes. `exec-once = hypridle` |
| [hyprpaper](pkgs/extra/hyprpaper) | 1.0.0 | Wallpapers: text art and patterns behind the windows. `exec-once = hyprpaper` |

## Quick demo run

```sh
pacman -Sy
pacman -Ss                        # browse everything
pacman -S lolcat fortune tree     # core picks
pacman -S sl cmatrix figlet       # extra fun
sudo pacman -S nano               # as a wheel user; sudo comes with byteos
fortune
tree /etc
sl
cmatrix
figlet ByteOS
```

## Layout

```
pkgs/<repo>/<name>/PKGBUILD.lua   package sources (edit these)
pkgs/<repo>/<name>/files/...
<repo>/<name>-<version>.bpk       built packages  (generated)
<repo>/<repo>.db                  repo database   (generated)
<repo>/<repo>.db.sig              its signature   (generated with --key)
```

The format is described in the ByteOS README on `master` and in
`lib/bpk.lua`.

## Adding or changing a package

1. Create or edit `pkgs/<repo>/<name>/` (`PKGBUILD.lua` + `files/`). When
   only the packaging changes, bump `rel`; otherwise bump `version`.
2. Rebuild and sign with the tool from a `master` checkout:
   ```sh
   lua <ByteOS-OC>/tools/mkrepo.lua --key ~/.config/byteos/repo-key.pem .
   ```
   This also writes `<repo>.db.sig`, which pacman checks with a tier 3 data
   card. Without `--key` the databases are unsigned and computers set to
   `SigLevel = Required` will refuse them.
3. Commit the sources together with the regenerated `<repo>/` files and push.
   Computers pick the change up on their next `pacman -Syu`.
