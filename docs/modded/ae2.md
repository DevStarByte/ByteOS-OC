# Applied Energistics 2

The `me-monitor` package shows an **Applied Energistics 2** network (an *ME network*)
on a ByteOS computer: its power, what is stored, the crafting CPUs, and items that run
low. A service can watch your stock and warn you when an item falls below a minimum you
set.

## Setting it up

1. Connect the computer to the ME network through an **ME Controller** or an
   **ME Interface**: by cable, or with an OpenComputers **Adapter** placed next to it
   (and connected to the computer by cable).
2. Install the package and look at the network:

    ```sh
    root@byteos ~# pacman -S me-monitor
    alice@byteos ~> me-monitor
    ```

If it says `no ME controller or ME interface found`, check the cable or adapter. An
adapter needs to touch the controller or interface itself.

## The overview

```text
Power   1,600,000 / 2,000,000 AE, using 214 AE/t, getting 300 AE/t
Items   312 kinds, 1,284,570 in all
CPUs    1 busy, 2 idle (Main)
low     Iron Ingot: 120 of 256

Most items
     524,288  Cobblestone  minecraft:cobblestone
     ...
```

`me-monitor` shows the stored power and its use, how many kinds of items there are and
how many in all, the crafting CPUs (busy and idle, with the busy ones' names), every
item below its minimum, and
the ten items you have most of. Items that can be crafted are marked `(craftable)`.

```sh
alice@byteos ~> me-monitor find ingot     # every item whose name contains "ingot"
alice@byteos ~> me-monitor watch          # the overview on the whole screen, every 2 seconds
```

In `watch`, ++q++ quits. It makes a good wall display next to the ME drive.

## Minimums and alerts

Tell `me-monitor` which items you want to keep in stock, in `/etc/me-monitor.conf`
(root). One line per item, by the name shown in the game or by the item's id:

```ini
minimum Iron Ingot 256
minimum minecraft:redstone 1000
minimum Certus Quartz Crystal 64
interval = 60
```

Names are matched without regard to upper and lower case. An id is anything with a `:`
in it. `interval` is how often the service checks, in seconds.

Check them by hand at any time:

```sh
alice@byteos ~> me-monitor check
low: Iron Ingot: 120 of 256
```

`me-monitor check` ends with status 1 when anything is low, so scripts can react to it
(`if not me-monitor check; ...; end`, see [Scripts](../using/scripting.md)).

### The service

The `me-monitor` service (`me-monitord`) checks the minimums every `interval` seconds:

```sh
root@byteos ~# systemctl enable --now me-monitor
alice@byteos ~> journalctl -u me-monitor
```

When an item runs low it writes that to the system log once, and again when the item is
back above its minimum, so a low item does not fill the log. When a notification daemon
runs (`dunst` on the [Hyprbyte desktop](../desktop/hyprbyte.md)), the alert also pops up
on the screen. Install `libnotify` and `dunst` for that.

Your edits to `/etc/me-monitor.conf` survive upgrades of the package.

!!! note "Tested against simulated hardware"
    `me-monitor` is tested against a simulated ME system that offers the functions of
    AE2's OpenComputers integration (`getItemsInNetwork`, `getCraftingCPUs`,
    `getStoredPower`, ...). If your version of the mod behaves differently, tell us on
    [GitHub](https://github.com/DevStarByte/ByteOS-OC/issues).
