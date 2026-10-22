# Reactors

The `reactorctl` package watches and controls **Big Reactors** and **Extreme Reactors**
(reactors and turbines) through OpenComputers. You can check them, switch them on and
off and set the control rods by hand, or let a service run the reactors so that the
energy buffer stays filled without burning fuel for nothing.

## Setting it up

1. Build the reactor with a **Computer Port** in its casing (it is one of the reactor's
   parts, like the power tap).
2. Connect the Computer Port to your ByteOS computer with OpenComputers **cable**.
   Turbines have a Computer Port too; connect them the same way.
3. Install the package:

    ```sh
    root@byteos ~# pacman -S reactorctl
    root@byteos ~# reactorctl
    ```

If `reactorctl` says `no reactor or turbine found (connect its Computer Port by cable)`,
check the cable and that the reactor is fully assembled. A reactor that is not assembled
shows as `not assembled`.

## Status

`reactorctl` shows every reactor and turbine:

```text
Reactor 1  3fa2b1c0  on
  Energy  6,200,000 / 10,000,000 RF (62%)
          █████████████████████████░░░░░░░░░░░░░░░
  Output  1,240 RF/t
  Fuel    3,800 / 4,000 mB (95%), waste 120 mB, burning 0.042 mB/t
  Heat    fuel 712 °C, casing 655 °C
  Rods    38% in (4 rods)
Turbine 1  7c01de44  on
  Rotor   1,796 RPM, inductor engaged
  Output  2,410 RF/t
  Energy  480,000 RF / 1,000,000 RF
```

For each reactor: on or off, the energy buffer and what it produces, fuel and waste (and
how fast fuel burns), temperatures and how far the control rods are in. An actively
cooled reactor shows the steam it makes instead of the buffer. For each turbine: on or
off, rotor speed, the inductor, output and energy. Reactors and turbines are numbered
in the order of their addresses, so the numbers can change when you add hardware.

`reactorctl watch` shows the same on the whole screen, refreshed every second; ++q++
quits.

## Control by hand

```sh
root@byteos ~# reactorctl on                 # start every reactor
root@byteos ~# reactorctl off 2              # stop reactor 2
root@byteos ~# reactorctl on turbine         # the same for turbines
root@byteos ~# reactorctl rods 40            # control rods 40 % in, every reactor
root@byteos ~# reactorctl rods 0 1           # reactor 1 at full power
```

Control rods slow the reaction down: `0` is full power, `100` almost none. All rods of a
reactor are set together.

## Automatic control

The `reactorctl` service runs `reactorctld`. Every few seconds it applies a simple rule
to each reactor:

- the control rods go in **as far as the energy buffer is full** (buffer 50 % full: rods
  50 % in), so the reactor makes about as much as is used;
- the rods move toward that level gradually (`smoothing`), not all at once;
- above `off_above` % the reactor is **stopped**; below `on_below` % it is **started**
  again.

Every change goes to the system log. Reactors that are **actively cooled** (they make
steam for turbines, not RF) are left alone.

```sh
root@byteos ~# reactorctl auto                       # try the rule once, see what it would change
root@byteos ~# systemctl enable --now reactorctl     # run it now and at every boot
root@byteos ~# journalctl -u reactorctl              # what it did
```

```text
reactor 1: control rods 38% -> 50% (buffer 62%)
reactor 1: stopped (buffer 96%)
```

The service is off until you enable it: it changes things in your world, so that is your
decision. `systemctl disable --now reactorctl` turns it off again.

### Settings

The rule's numbers are in `/etc/reactorctl.conf`. The service reads the file again when
it changes, so there is no need to restart it.

```ini
# stop a reactor when its buffer is fuller than this (%)
off_above = 95
# start it again when the buffer is below this (%)
on_below = 20
# how far the rods move toward their goal each step (0.05-1; 1 = at once)
smoothing = 0.5
# seconds between steps
interval = 5
```

Your edits survive upgrades of the package.

!!! note "Tested against simulated hardware"
    `reactorctl` is tested against a simulated reactor that offers the functions of the
    Big/Extreme Reactors integration (`getEnergyStored`, `setAllControlRodLevels`,
    ...). Newer Extreme Reactors report the buffer's capacity; for older versions
    10,000,000 RF is assumed. If your mod version behaves differently, tell us on
    [GitHub](https://github.com/DevStarByte/ByteOS-OC/issues).

## Limits

- The rod level shown is that of the first rod; the rule sets all rods together.
- Turbines have status and on/off, but no automatic control (inductor, flow rate).
