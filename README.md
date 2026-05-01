# ByteOS

> An Arch-Linux-flavoured operating system for the **OpenComputers** Minecraft mod.

ByteOS reimagines Arch Linux inside a virtual computer running on Lua 5.3/5.4.
You get a familiar layout (`/bin`, `/etc`, `/home`, `/usr`, `/var`), a colourful shell prompt
in the classic `[user@host pwd]$` style, an Arch-style **`pacman`** package manager,
**`neofetch`**, an `init` system that prints `[ OK ]` lines, the works.

```
   ____        _        ___  ____
  | __ ) _   _| |_ ___ / _ \/ ___|
  |  _ \| | | | __/ _ \ | | \___ \
  | |_) | |_| | ||  __/ |_| |___) |
  |____/ \__, |\__\___|\___/|____/
         |___/
```

## Features

- **ByteBIOS** — flashable EEPROM bootloader that finds and boots `/init.lua`.
- **bytekernel** — VFS with mountable component filesystems, cooperative process
  scheduler, signal/event loop, `require()` package loader.
- **systemd-style init** — prints `[ OK ]` boot messages, loads core libs, drops to
  a login prompt seeded from `/etc/passwd`.
- **ByteShell** — POSIX-ish shell with built-ins (`cd`, `exit`, `export`, `set`),
  Arch-coloured prompt, quoting, and a Lua execution environment per command.
- **Coreutils** — `ls cat echo pwd mkdir rm cp mv clear uname whoami edit help neofetch reboot shutdown`.
- **pacman** — `-S / -R / -Q / -Qi / -Sy / -Syu / -Ss` with a tiny on-disk repo format.
- **/etc/os-release**, **/etc/motd**, **/etc/hostname**, **/etc/passwd**, **/etc/pacman.conf**, **/etc/profile**, **/etc/fstab**.

## Repository Layout

```
ByteOS/
├── boot/
│   ├── eeprom.lua        ← flash to an EEPROM (ByteBIOS)
│   └── kernel.lua        ← kernel, loaded by /init.lua
├── init.lua              ← entry point invoked by ByteBIOS
├── sbin/init.lua         ← PID 1 / userspace init
├── lib/                  ← shell + term libs (loadable via require)
├── bin/                  ← user commands (.lua)
├── etc/                  ← system configuration
├── home/root/            ← root's home
├── var/lib/pacman/       ← pacman local DB
└── repo/                 ← sample pacman repo (mount as /mnt/repo)
```

## Installing inside Minecraft (OpenComputers)

You will need:

- A computer case (any tier)
- CPU + RAM (at least Tier 1.5; the OS is small but uses ~64 KiB)
- An EEPROM
- A managed hard disk drive
- A screen + keyboard + GPU (any tier)

### Easiest way: just copy the files onto a disk

ByteOS now has a **first-boot setup wizard**. You don't need to run any installer
script — just put the files on a disk and boot it.

1. Flash `boot/eeprom.lua` onto your EEPROM (see "Flash the EEPROM" below).
2. Copy the contents of this repository onto the target HDD so the disk root
   contains `/init.lua`, `/boot/`, `/sbin/`, `/lib/`, `/bin/`, `/etc/`, `/home/`,
   `/var/`. From outside Minecraft you can drop the files straight into
   `saves/<world>/opencomputers/<disk-uuid>/`.
3. Set the EEPROM's boot address to that disk (or just have it as the only
   bootable FS).
4. Power on. On the very first boot ByteOS notices `/etc/.installed` is missing
   and runs the setup wizard:
   ```
   ==========================================
           ByteOS First-Time Setup
   ==========================================

   No install detected. Let's configure your system.

   Hostname [byteos]: my-rig
   Username  [root]: thomas
   Password: ********
   Confirm:  ********

   Setup complete. You can now log in as 'thomas'.
   my-rig login: thomas
   Password: ********
   ```
   Your answers are written to `/etc/hostname` and `/etc/passwd`, and a
   `/etc/.installed` marker is created so the wizard never runs again.
5. From now on every boot goes straight to the login prompt and verifies your
   password.

> Want to redo the setup? Just delete `/etc/.installed` and reboot.

### Optional: use the bundled `install.lua` from OpenOS

The old installer is still included for the case where you want to copy the
files **from another disk** (e.g. a floppy under OpenOS) and optionally flash
the EEPROM in one go:

1. Boot any OpenOS computer.
2. Insert a disk/floppy that contains this repository.
3. Insert a blank target HDD for ByteOS.
4. From the OpenOS shell run:
   ```
   lua /mnt/<id_of_byteos_disk>/install.lua
   ```
5. The installer asks for source / target FS, wipes the target, copies all
   ByteOS files and (optionally) flashes ByteBIOS. Reboot afterwards — the
   first-boot wizard above takes care of the rest.

> If you ever see `unrecoverable error init:4: /lib/core/boot.lua` after copying
> ByteOS, that means OpenOS files are still on the disk. Wipe the disk (or
> re-run `install.lua`) before copying ByteOS over it.

### Flash the EEPROM

From any working Lua prompt (e.g. an OpenOS install on a floppy):
```lua
local f = io.open("/path/to/ByteOS/boot/eeprom.lua", "r")
local code = f:read("*a"); f:close()
component.eeprom.set(code)
component.eeprom.setLabel("ByteBIOS")
-- Optional: pin the boot device
-- component.eeprom.setData(component.<your-disk>.address)
```

## A short tour

```sh
[root@byteos ~]# neofetch
[root@byteos ~]# uname -a
ByteOS byteos 1.0.0 (Iron) lua54 GNU/ByteOS

[root@byteos ~]# pacman -Sy
:: synchronized core
:: synchronized extra

[root@byteos ~]# pacman -Ss cow
core/cowsay 0.2.0
    ascii-art talking cow

[root@byteos ~]# pacman -S cowsay
:: installing cowsay (0.2.0) from core
:: installed cowsay

[root@byteos ~]# cowsay "I run Arch... ish."
 -------------------
< I run Arch... ish. >
 -------------------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||

[root@byteos ~]# pacman -Q
bytekernel 1.0.0
coreutils 1.0.0
pacman 1.0.0
cowsay 0.2.0
```

## Writing your own packages

A package is just a Lua file that returns a table:

```lua
return {
  files = {
    ["/usr/bin/mytool.lua"] = "term.write('hi\\n') return 0\n",
  },
  post_install = function() --[[ optional ]] end,
}
```

Drop it into a repo directory next to `repo.db`, add a line
`mytool 1.0.0 my cool tool`, and `pacman -Sy && pacman -S mytool`.

## Hacking on ByteOS

Each command in `bin/` runs in a sandbox where the following globals are pre-injected:
`term`, `shell`, `fs` (= `kernel.fs`), `k` (= `kernel`), and `arg` (the argv list).
Just write a `.lua` file that uses them and `return` an exit code.

## License

MIT. See LICENSE.

> Minecraft is a trademark of Mojang AB. OpenComputers © Sangar et al.
