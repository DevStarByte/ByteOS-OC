# Robots and drones

The `robot` package drives OpenComputers **robots** and **drones** from the shell: move,
turn, dig, place, sort the inventory. It can also run a list of steps from a file, so a
robot can dig a tunnel or build a wall while you do something else.

## Robots run ByteOS too

A robot is a computer on its own (it has a CPU, memory and a disk), so you install
ByteOS on it like on any computer and run `robot` there. The commands talk to the robot
they run on. On an ordinary computer, `robot` says `this is not a robot (no robot
component)`.

```sh
root@byteos ~# pacman -S robot
root@byteos ~# robot info
```

## Commands

| Command | What it does |
|---|---|
| `robot move forward/back/up/down [N]` | N steps (default 1) |
| `robot turn left/right/around` | turn on the spot |
| `robot dig [front/up/down]` | swing the tool (default front) |
| `robot place [front/up/down]` | place the selected block |
| `robot use [front/up/down]` | right-click |
| `robot detect` | what is in front, above and below |
| `robot select N` | pick inventory slot N |
| `robot drop [N] [front/up/down]` | drop N items of the selected slot (default all) |
| `robot suck [N] [front/up/down]` | take N items (default all) |
| `robot info` | name, energy, tool, inventory |
| `robot run FILE` | run the steps in a file |

Where a command takes a choice such as `forward/back/up/down`, give one of the words:
`robot move up 2`. A robot can dig, place, use, drop and take only in front, above and
below, not behind it: turn first.

```sh
alice@byteos ~> robot move forward 3
alice@byteos ~> robot turn left
alice@byteos ~> robot dig up
alice@byteos ~> robot select 2
alice@byteos ~> robot place down
alice@byteos ~> robot detect
front  solid
up     air
down   solid
```

`robot info` shows the robot's name, its energy, how much of the tool is left and every
inventory slot that holds something, plus the selected slot (marked `<`):

```text
Robbie
energy   18000 / 20000
tool     74% left
slots    16 (slot 2 selected)
   1   64 items
   2   12 items  <
```

When a move is blocked, you get OpenComputers' own reason and how far the robot got:

```text
robot: move forward: solid (after 2 of 5 steps)
```

## Step files

A step file lists the commands above, one per line, without the word `robot`. `#`
starts a comment, and `repeat N` ... `end` runs the lines between N times (repeats can
be nested).

```text
# tunnel.txt: a 2-high tunnel, 10 blocks long
repeat 10
  dig
  dig up
  move forward
end
turn around
move forward 10
```

```sh
alice@byteos ~> robot run tunnel.txt
```

The file is checked first: a `repeat` without `end`, or an `end` without `repeat`, is
reported with its line before the robot moves. While it runs, the first step that fails
stops everything, with its line number and status 1:

```text
robot: tunnel.txt, line 4: move forward: solid
```

!!! warning "Digging where there is nothing"
    `dig` counts as a failed step when there is nothing to dig (air, a cave), so a step
    file stops at the first gap in the rock. Check first with `detect`, or keep step
    files to ground you know.

A step file cannot run another step file.

## Drones

A drone is a small flying robot with its own little program on its EEPROM. When a drone
is in reach of a computer that controls it, or when ByteOS runs on the drone, `robot
drone` flies it:

```sh
alice@byteos ~> robot drone move 0 5 0      # 5 blocks up (DX DY DZ)
alice@byteos ~> robot drone info            # name, offset, speed, energy
```

The *offset* in `info` is how far the drone still has to fly to where you sent it.

!!! note "Tested against simulated hardware"
    `robot` is tested against simulated robot and drone components that offer
    OpenComputers' robot API (`move`, `turn`, `swing`, `place`, `detect`, ...). If your
    version behaves differently, tell us on
    [GitHub](https://github.com/DevStarByte/ByteOS-OC/issues).
