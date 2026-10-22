---
title: ByteOS
template: home.html
hide:
  - navigation
  - toc
---

<h2 class="bx-section">Everything a Linux user expects, in a Minecraft computer</h2>

<div class="grid cards bx-cards" markdown>

-   :material-console-line:{ .bx-icon } **A shell you'll enjoy**

    ---

    Modelled on fish: colours while you type, grey suggestions from your
    history, Tab completion, pipes, and scripts with `if`, `for` and `function`.

    [:octicons-arrow-right-24: The shell](using/shell.md) · [Scripts](using/scripting.md)

-   :material-package-variant-closed:{ .bx-icon } **pacman, the real way**

    ---

    `pacman -S` installs editors, games, monitors, an IRC client, `tar`,
    `gzip` and more. `pacman -Syu` upgrades everything, ByteOS itself included,
    with rollback if something goes wrong.

    [:octicons-arrow-right-24: pacman](packages/pacman.md) · [All packages](packages/list.md)

-   :material-account-lock:{ .bx-icon } **Users, sudo, services**

    ---

    Accounts with hashed passwords, file permissions, `sudo`, background jobs,
    systemd-style services, a system log and cron.

    [:octicons-arrow-right-24: Users](using/users.md) · [Services and logs](using/processes.md)

-   :material-lan-connect:{ .bx-icon } **Networking**

    ---

    Messages, files, remote shells and shared folders between computers;
    downloads, pastebin, GitHub and IRC through the internet card.

    [:octicons-arrow-right-24: ByteNet](network/bytenet.md) · [The internet](network/internet.md)

-   :material-view-dashboard-variant:{ .bx-icon } **A tiling desktop**

    ---

    Hyprbyte works like Hyprland: windows side by side, nine workspaces, a bar,
    notifications, a launcher and a lock screen.

    [:octicons-arrow-right-24: Hyprbyte](desktop/hyprbyte.md)

-   :material-factory:{ .bx-icon } **Made for modded worlds**

    ---

    Run Big Reactors on autopilot, watch an AE2 network, script robots and
    drones, draw holograms and play music on note blocks.

    [:octicons-arrow-right-24: Modded Minecraft](modded/index.md)

</div>

<h2 class="bx-section">Install with two commands</h2>

<div class="bx-install" markdown>

Build a computer with an **internet card** and a blank **hard disk**, boot the
OpenOS floppy and type:

```sh
wget -f https://raw.githubusercontent.com/DevStarByte/ByteOS-OC/master/install.lua /tmp/install.lua
/tmp/install.lua
```

Answer the questions, take the floppy out, and ByteOS boots into its setup.
[Installing](getting-started/install.md) walks through every question and what to craft.

</div>

<h2 class="bx-section">Stuck?</h2>

[Troubleshooting](getting-started/troubleshooting.md) covers the usual problems: a disk
that will not boot, too little memory, a package that will not install. Inside ByteOS,
`help` lists every command and `man <command>` explains one; the
[command reference](reference/commands.md) has the same pages here. ByteOS is free
software under the MIT licence; the source, the issues and the
[changelog](https://github.com/DevStarByte/ByteOS-OC/blob/master/CHANGELOG.md) are
[on GitHub](https://github.com/DevStarByte/ByteOS-OC).
