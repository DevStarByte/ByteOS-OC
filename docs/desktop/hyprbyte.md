# Hyprbyte

Hyprbyte is a tiling window manager in the spirit of Hyprland: every window is a
terminal with its own shell (or one program), new windows split the free space, and
there are nine workspaces. Around it, a handful of packages make up a full desktop: a
bar, notifications, a launcher, a lock screen and wallpapers. This page covers all of
them.

## Install and start

```sh
root@byteos ~# pacman -S hyprbyte quickshell
alice@byteos ~> echo "exec-once = quickshell" >> ~/.config/hyprbyte.conf
alice@byteos ~> start-hyprbyte
```

Hyprbyte is started from the shell after you log in; it is not a login session.
++alt+enter++ opens a terminal, ++alt+shift+e++ quits and brings you back to the shell.
`start-hyprbyte --no-animations` passes options on to Hyprbyte.

!!! note "Memory"
    Each window is a shell plus a screen buffer. Two or three windows are comfortable
    with Tier 2 memory; with Tier 3 memory you can open more.

Like Hyprland, Hyprbyte draws no bar of its own. That is what Quickshell is for, which
is why the example above installs it and starts it with `exec-once`.

## Keys

`Mod` is ++alt++ unless you change it in the settings (`mod = super` or `mod = ctrl`).

| Keys | What they do |
|---|---|
| ++alt+enter++ | open a new terminal |
| ++alt+d++ | run a program (with `rofi` installed: its launcher; otherwise a small box) |
| ++alt+w++ | switch to any window (needs `rofi`) |
| ++alt+l++ | lock the screen (needs `hyprlock`) |
| ++alt+q++ | close the window in focus |
| ++alt+arrow-left++ ++alt+arrow-right++ ..., ++alt+tab++ | focus the previous / next window (a click focuses too) |
| ++alt+shift+arrow-left++ ... | move the window back / forward in the layout |
| ++alt+f++ | full screen on / off |
| ++alt+1++ ... ++alt+9++ | go to workspace 1 to 9 |
| ++alt+shift+1++ ... ++alt+shift+9++ | send the window in focus there |
| ++alt+shift+e++ | quit Hyprbyte (every window is closed) |

Every other key goes to the window in focus, ++ctrl+c++ included.

## Settings

Hyprbyte reads `/etc/hyprbyte.conf` (for everyone), then `~/.config/hyprbyte.conf`
(yours, which wins). The format is `key = value`, as in `hyprland.conf`:

```ini
mod = alt                  # alt, super (the Windows key) or ctrl
gaps_in = 1                # space between windows
gaps_out = 1               # space around them
animations = yes           # windows pop open
rounding = yes             # rounded corners on the frames

open = btop                # open a window running this at the start (any number)
exec-once = quickshell     # run this in the background at the start, without a window

bind = MOD, B, exec, btop             # your own keys
bind = MOD SHIFT, R, spawn, rofi -show run
```

A `bind` line takes modifiers (`MOD`, `SHIFT`, `CTRL`), a key (`A`-`Z`, `0`-`9`,
`RETURN`, `SPACE`, `TAB`, `LEFT`, `F1`, ...), a dispatcher (see below) and what the
dispatcher gets. Binding the same keys as a built-in shortcut replaces it. What
`exec-once` programs print goes to the system log.

## hyprctl

From any Hyprbyte window, `hyprctl` tells you about the windows and does what a key
would do:

```sh
alice@byteos ~> hyprctl clients              # every window: id, workspace, title, pid
alice@byteos ~> hyprctl workspaces
alice@byteos ~> hyprctl activewindow
alice@byteos ~> hyprctl layers               # bars, pop-ups and wallpapers
alice@byteos ~> hyprctl dispatch exec btop   # open a window running btop
```

| Dispatcher | What it does |
|---|---|
| `exec <command>` | open a window running the command |
| `spawn <command>` | run it in the background, without a window (`rofi`, `hyprlock`, ...) |
| `focuswindow <id>` | bring that window into focus |
| `workspace <n>` | go to workspace n |
| `movetoworkspace <n>` | send the window in focus there |
| `killactive` | close the window in focus |
| `fullscreen` | full screen on / off |
| `cyclenext` / `cycleprev` | focus the next / previous window |
| `exit` | quit Hyprbyte |

The same dispatchers are used in `bind` lines.

## A bar: Quickshell

Quickshell draws panels (bars) along the top or bottom of the screen, made of widgets you
list in a Lua file. It is ByteOS's take on Quickshell for Hyprland, with Lua where that
one has QML.

Start it with `exec-once = quickshell` in `~/.config/hyprbyte.conf`, or from a window
with `quickshell &` (`qs` is the same). Without a file of your own you get the default
bar: workspaces, the window title, memory, energy and a clock.

Your bar goes in `~/.config/quickshell/shell.lua`. Copy `/etc/xdg/quickshell/shell.lua`
as a start. When you save the file, the bar changes within two seconds:

```lua
return {
  PanelWindow {
    anchor = "top",                                -- or "bottom"
    Workspaces {},                                 -- click one to go there
    ActiveWindow { max = 30 },
    Spacer {},
    Command { cmd = "uptime -p", interval = 60 },  -- what a command prints
    Button { text = "btop", onClick = "btop" },    -- opens it in a window
    Clock { format = "%H:%M " },
  },
}
```

| Widget | Shows |
|---|---|
| `Text { text = "..." }` | text, or what a function returns |
| `Clock { format = "%a %H:%M" }` | the time (codes as in `date`) |
| `Workspaces { shown = 5 }` | the workspaces; click one to go there |
| `ActiveWindow { max = 40 }` | the title of the window in focus |
| `Memory { format = "mem %d%%" }` | memory in use |
| `Energy { format = "%d%%" }` | the energy stored (hidden without a battery) |
| `Command { cmd = "...", interval = 10 }` | the first line a command prints, again every `interval` seconds |
| `Button { text = "...", onClick = "btop" }` | a button; a command opens in a window, a function is called |
| `Separator {}`, `Spacer {}`, `Row { ... }` | a divider, free room, widgets kept together |

Every widget also takes `color` (a theme name such as `"accent"`, `"green"`, `"muted"`,
or a number like `0xFF8800`), `bg` and `padding`. A `PanelWindow` takes `anchor`,
`height` and `color`; the file may return several of them. `man quickshell` has the full
list.

## Notifications: dunst and libnotify

`dunst` shows notifications as pop-ups in the top right corner. Anything sent with
`notify-send` appears there, and so do messages from other computers (see
[ByteNet](../network/bytenet.md)) and alerts from packages such as `me-monitor`. A click
closes a pop-up; critical ones stay until clicked.

```sh
root@byteos ~# pacman -S dunst           # brings libnotify along
alice@byteos ~> echo "exec-once = dunst" >> ~/.config/hyprbyte.conf
alice@byteos ~> notify-send "Backup done" "42 files saved"
alice@byteos ~> notify-send -u critical "Reactor" "too hot!"
alice@byteos ~> dunstctl history           # the last notifications
alice@byteos ~> dunstctl set-paused true   # do not disturb (critical ones still show)
```

`notify-send` takes `-u low|normal|critical`, `-t SECONDS` (`-t 0` keeps it until it is
clicked away) and `-a APP`. `dunstctl` also has `close`, `close-all`, `is-paused` and
`count`. Settings (`width`, `timeout`, `max`) are in `~/.config/dunst/dunstrc`; copy
`/etc/dunst/dunstrc` to start.

## Launcher: rofi

`rofi` opens a box in the middle of the screen. Type a few letters of a program; they
need not be next to each other (`sctl` finds `systemctl`). Pick one with the arrows and
press ++enter++ to open it in a window. Text with spaces runs as typed (`ping box2`).
++tab++ copies the pick into the line, ++esc++ closes the box.

- ++alt+d++ (or `rofi -show run`): programs
- ++alt+w++ (or `rofi -show window`): the open windows, on every workspace

## Lock and idle: hyprlock and hypridle

`hyprlock` hides every window behind a big clock until you type your password and press
++enter++. Nothing you type reaches the windows meanwhile, and each wrong password makes
it wait a little longer. Lock with ++alt+l++.

`hypridle` runs commands when nobody has touched the keyboard or mouse for a while. Its
settings are in `~/.config/hypr/hypridle.conf` (copy `/etc/hypr/hypridle.conf`):

```ini
listener = 300, hyprlock                    # lock after five minutes
listener = 60, notify-send "still there?"
```

Each listener runs once per idle time; a key or click starts the count again. Start it
with `exec-once = hypridle`.

## Wallpapers: hyprpaper

`hyprpaper` fills empty workspaces and the gaps between windows: a text picture in the
middle and a pattern around it. Settings are in `~/.config/hypr/hyprpaper.conf` (copy
`/etc/hypr/hyprpaper.conf`); changes show within two seconds:

```ini
wallpaper = /usr/share/hyprpaper/mountains.txt   # or byteos.txt, cat.txt, or none
pattern = stars                                  # dots, grid, stars, waves or none
color = accent                                   # theme colour names
pattern_color = raised
```

Any text file works as a picture. Start it with `exec-once = hyprpaper`.

## A full setup

```sh
root@byteos ~# pacman -S hyprbyte quickshell dunst rofi hyprlock hypridle hyprpaper
alice@byteos ~> edit ~/.config/hyprbyte.conf
```

```ini
exec-once = quickshell
exec-once = dunst
exec-once = hyprpaper
exec-once = hypridle
open = btop
bind = MOD, B, exec, btop
```

```sh
alice@byteos ~> start-hyprbyte
```

## For programmers: layers

Other programs can draw panels, overlays and backgrounds through the state Hyprbyte
shares; this is how Quickshell, dunst and hyprpaper work. `man hyprbyte` documents it
(`hypr.addLayer`, anchors `top`, `bottom`, `overlay`, `background`, `hypr.grab` for
keys).

```lua
local hypr = package.loaded["hyprbyte.state"]   -- nil: Hyprbyte is not running
local layer = hypr.addLayer({ namespace = "mybar", anchor = "bottom", height = 1,
  draw = function(gpu, x, y, w, h) gpu.set(x, y, "hello") end })
```
