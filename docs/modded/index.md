# Modded Minecraft

OpenComputers can talk to the machines of many other mods: reactors, storage networks,
robots and more. ByteOS has packages that turn this into ready-made commands and
services, so you can watch and control your base from a terminal without writing Lua
first. This page explains how other mods' blocks reach a computer, and which package
covers what.

## How other mods' blocks reach a computer

A computer works with *components*: its own parts (GPU, disks, cards) and any block
connected to it that offers functions to call. Other mods' blocks become components in
one of two ways:

- **By cable.** Some mods make a block that is a component by itself. Big Reactors and
  Extreme Reactors have the **Computer Port** for this; you connect it to the computer
  with OpenComputers cable.
- **Through an adapter.** OpenComputers' **Adapter** block turns the blocks touching it
  into components, as far as the mod (or OpenComputers' built-in support for it) offers
  that. Put the adapter next to the machine and connect the adapter to the computer by
  cable.

Robots and drones are computers themselves, and the hologram projector is an
OpenComputers block that you connect by cable.

## Seeing what is connected

The `lshw` package lists every component with what OpenComputers reports about it:

```sh
root@byteos ~# pacman -S lshw
alice@byteos ~> lshw -short
```

Without it, the `lua` prompt does the same in one line:

```sh
alice@byteos ~> lua -e 'for addr, kind in component.list() do print(kind, addr) end'
```

The *kind* (`br_reactor`, `me_controller`, `hologram`, ...) is what programs look for.
If a machine does not show up, check the cable, the adapter and that the machine itself
is complete (a reactor that is not fully assembled has no working Computer Port).

## The packages

<div class="grid cards" markdown>

-   **Reactors** (`reactorctl`)

    ---

    Status of Big/Extreme Reactors and turbines, switching them on and off, control
    rods, and a service that keeps the energy buffer filled without wasting fuel.

    [:octicons-arrow-right-24: Reactors](reactors.md)

-   **Applied Energistics 2** (`me-monitor`)

    ---

    Power, stored items and crafting CPUs at a glance, item search, and alerts when an
    item falls below its minimum.

    [:octicons-arrow-right-24: Applied Energistics 2](ae2.md)

-   **Robots and drones** (`robot`)

    ---

    Move, dig, place and sort inventory from the shell, or run a list of steps from a
    file.

    [:octicons-arrow-right-24: Robots and drones](robots.md)

-   **Holograms and music** (`holo`, `play`)

    ---

    Text and shapes on a hologram projector; tunes on the speaker, note blocks or
    Computronics iron note blocks.

    [:octicons-arrow-right-24: Holograms and music](holo-music.md)

</div>

The `redstone` package (see the [package list](../packages/list.md)) reads and sets
redstone signals and bundled cables, which many mods' machines react to.

!!! note "Tested against simulated hardware"
    These packages are tested against simulated machines that behave like the mods'
    OpenComputers integrations. Mods change between versions; every call is guarded, so
    a function a version lacks shows as `?` instead of crashing. If something behaves
    differently with your mod version, tell us on
    [GitHub](https://github.com/DevStarByte/ByteOS-OC/issues).

## Tips

- **Power.** Computers, robots and holograms need energy. `power` (a package) shows the
  computer's stored energy and how long it lasts; `btop` shows it too.
- **Services keep running.** The automatic parts (`reactorctl`, `me-monitor`) are
  services: once enabled, they start at every boot and write to the system log
  (`journalctl -u <name>`). See [Programs, services and logs](../using/processes.md).
- **Notifications.** With the [Hyprbyte desktop](../desktop/hyprbyte.md) and `dunst`,
  alerts appear as pop-ups.
- **A wall screen.** `reactorctl watch` and `me-monitor watch` fill the screen and
  refresh by themselves: a good use for a big screen next to the machines.
