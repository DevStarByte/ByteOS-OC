# Programs, services and logs

ByteOS can run programs in the background while you keep working. This page
covers background jobs, services that start at boot, the system log, scheduled
jobs, and the time.

## Background jobs

Put `&` at the end of a command line and it runs in the background. The shell
prints a job number and a process id (pid), and the prompt comes back at once:

```sh
alice@byteos ~> sleep 60 && echo done &     # the whole line runs in the background
[1] 4
alice@byteos ~> jobs                         # this terminal's jobs
[1]  Running      4  sleep 60 && echo done
alice@byteos ~> ps                           # every process, with its user
alice@byteos ~> fg                           # wait for the newest job (fg %1 for job 1)
alice@byteos ~> wait                         # wait until all jobs have finished
alice@byteos ~> kill %1                      # stop job 1 (or: kill 4, by pid)
```

Before the next prompt, the shell tells you which jobs ended
(`[1]  Done  sleep 60 && echo done`).

How it works, and the limits that follow from it:

- ByteOS shares the processor between programs **cooperatively**. Background
  programs run while the program in front waits: at the prompt, in `sleep`, or
  while waiting for a key or a network message.
- A background job **never gets keyboard input**. `fg` lets you wait for a job
  and stop it with ++ctrl+c++, but you can't type into it.
- Each process runs as the user who started it. You may `kill` your own
  processes; root may kill any.
- A process has its own working directory: `cd` in a job does not move your
  shell.

### Stopping a program: Ctrl+C

++ctrl+c++ stops the program in front while it waits for a key or an event, and
skips the rest of the command line (exit status 130). At the prompt it only
clears the line you are typing.

!!! warning "Programs must wait now and then"
    OpenComputers stops a computer whose program runs for a few seconds without
    ever waiting. ByteOS's own long loops pause briefly on their own. A program
    you write should call `k.event.pull` (or `sleep`) in long loops. This also
    lets ++ctrl+c++ and background jobs get through.

## Services

A **service** is a program that runs in the background on its own, usually
from boot. ByteOS comes with a few:

| Service | What it does | On by default |
|---|---|---|
| `netd` | answers other computers on [ByteNet](../network/bytenet.md) | yes |
| `timesyncd` | keeps the clock on real time (needs an internet card) | yes |
| `crond` | runs [scheduled jobs](#scheduled-jobs) | no |

Packages add more (`rshd`, `netfsd`, `timerd`, `reactorctl`, ...).

```sh
alice@byteos ~> systemctl                          # every service and its state
alice@byteos ~> systemctl status netd              # state, pid and its last log lines
root@byteos ~# systemctl start crond               # start now
root@byteos ~# systemctl stop crond
root@byteos ~# systemctl restart netd
root@byteos ~# systemctl enable --now crond        # start at every boot, and now
root@byteos ~# systemctl disable --now crond       # not at boot any more, and stop it
```

Starting, stopping, enabling and disabling need root. The enabled services
are listed in `/etc/systemd/enabled`. At boot, each one shows an
`[ OK ] Started ...` line.

### Writing your own service

A service is described by a small file, `/etc/systemd/system/<name>.service`
(packages put theirs in `/usr/lib/systemd/system`):

```ini
[Unit]
Description=Backup every hour

[Service]
ExecStart=/usr/bin/backupd --quiet
User=root
Restart=on-failure
RestartSec=5
```

| Key | Meaning |
|---|---|
| `Description` | the name shown at boot and by `systemctl` |
| `ExecStart` | the command line to run, as you would type it in the shell (required) |
| `User` | who it runs as (default `root`) |
| `Restart` | `no` (default), `on-failure` (again after a crash or a non-zero exit) or `always` |
| `RestartSec` | seconds to wait before restarting (default 5) |

A service that keeps failing is restarted at most five times in a row. What a
service prints, error messages included, goes to the system log under its
name. `man systemd.service` has the same summary inside ByteOS.

A minimal service program waits in a loop:

```lua
-- /usr/bin/backupd.lua
while true do
  print("backing up")                  -- goes to the log: journalctl -u backup
  shell.execute("cp -r /home /mnt/1a2b3c4d/backup")
  k.event.pull(3600)                   -- wait an hour (and let others run)
end
```

## The system log

Boot messages, logins and failed logins, `sudo` and `su`, package changes,
services and crashed programs are written to `/var/log/messages`, one line each:

```text
Oct 21 14:03:12 byteos sudo: alice : PWD=/home/alice ; USER=root ; COMMAND=pacman -Syu
```

```sh
alice@byteos ~> journalctl -n 20           # the last 20 lines
alice@byteos ~> journalctl -u sudo         # only lines from one program or service
alice@byteos ~> journalctl -f              # keep showing new lines (Ctrl+C ends it)
alice@byteos ~> dmesg                      # everything since boot, with seconds since power-on
alice@byteos ~> logger -t backup done      # write your own line, tagged "backup"
```

The log file is kept small for OpenComputers disks: past 32 KiB, its older
half is dropped. `dmesg` keeps the last 300 messages since boot in memory.

## Scheduled jobs

To run something regularly (every night, every 15 minutes), use `crontab`. Each
user's jobs are in their `~/.crontab`, one per line: five time fields, then the
command.

```sh
alice@byteos ~> crontab -e         # edit your jobs (in edit, or $EDITOR)
alice@byteos ~> crontab -l         # show them
alice@byteos ~> crontab -r         # remove them all
alice@byteos ~> crontab jobs.txt   # install them from a file (crontab - reads a pipe)
```

```text
# min  hour  day  month  weekday  command
*/15   *     *    *      *        echo still here
0      7     *    *      mon-fri  sh ~/bin/morning.sh
30     2     *    *      *        tar -czf /mnt/3f2a91c0/home.tar.gz -C /home alice
@daily                            rm -r /tmp/cache
```

| Field | Values |
|---|---|
| minute | 0–59 |
| hour | 0–23 |
| day of the month | 1–31 |
| month | 1–12 or `jan`–`dec` |
| weekday | 0–7 (0 and 7 are Sunday) or `sun`–`sat` |

Each field takes `*` (any), a number, a range (`1-5`), a step (`*/15`,
`0-30/10`) or a list (`1,15`). When both day and weekday are given, either one
matching is enough. Instead of the five fields you can write `@hourly`,
`@daily`, `@weekly`, `@monthly`, `@yearly`, or `@reboot` (once, when crond
starts).

`crontab` checks the lines before saving and tells you which line is wrong.

The jobs are run by the **`crond`** service, which is off until someone needs
it, to save memory. When root installs a crontab, `crontab` offers to start it.
Otherwise:

```sh
root@byteos ~# systemctl enable --now crond
```

A job runs as its user, in their home folder, in the background. What it prints
goes to the log (`journalctl -u crond`). Root can also put jobs in
`/etc/crontab`, with a user name before the command:

```text
0 3 * * *  alice  sh /home/alice/bin/cleanup.sh
```

!!! note "Which time?"
    Jobs go by the real time once `timesyncd` has it (see [Time](#time)).
    Without an internet card they go by the Minecraft world's time, where a
    minute passes in under a second, so `*/15` comes round very quickly.

### Timers (systemd style)

The `timers` package (`sudo pacman -S timers`) starts services on a schedule
instead, systemd style. A timer is `/etc/systemd/system/<name>.timer`, next to
the service it starts:

```ini
[Unit]
Description=Back up every night

[Timer]
OnCalendar=daily
OnBootSec=2min
OnUnitActiveSec=1h
Unit=backup.service
```

| Key | Meaning |
|---|---|
| `OnCalendar` | when: `hourly`, `daily`, `weekly`, `14:30`, `*:15` (every hour at quarter past), `*:00/10` (every ten minutes), `Mon,Fri 08:00` |
| `OnBootSec` | once, this long after boot (`90`, `30s`, `5min`, `2h`, `1d`, `1h 30min`) |
| `OnUnitActiveSec` | again, this long after each start |
| `Unit` | the service to start (default: the one with the timer's name) |

A timer needs at least one of `OnCalendar`, `OnBootSec` or `OnUnitActiveSec`.

```sh
alice@byteos ~> timers                 # every timer, when it runs next and last ran
root@byteos ~# timers enable backup
root@byteos ~# timers start backup     # run its service now
```

`man systemd.timer` explains the details. Use crontab for "run this command";
use timers when the job already is a service.

## Time

OpenComputers' own clock is the Minecraft world's time. With an **internet
card**, the `timesyncd` service fetches the real time at boot and every hour,
and your time zone applies, daylight saving time included.

```sh
alice@byteos ~> date                               # e.g. Wed Oct 21 14:03:12 CEST 2026
alice@byteos ~> date "+%A, %d %B %Y %H:%M"         # your own format
alice@byteos ~> date -u                            # in UTC
alice@byteos ~> timedatectl                        # local time, UTC, zone, synced or not
alice@byteos ~> timedatectl list-timezones
root@byteos ~# timedatectl set-timezone Europe/Berlin
root@byteos ~# timedatectl sync                    # fetch the real time now
```

Without an internet card, `date` shows the world's time and the zone says
"world". The log uses the real time once it is synchronized.

`date +FORMAT` understands `%Y %m %d %H %M %S %a %A %b %B %e %j %y %I %p %Z %z %F %T %s`.

## Timing commands

```sh
alice@byteos ~> time pacman -Sy            # how long it took: real 1.25s
alice@byteos ~> timeout 30 ping box2       # stop it after 30 s (exit status 124)
alice@byteos ~> timeout 1.5m sh build.sh   # durations take s, m, h, d
alice@byteos ~> watch -n 5 df              # rerun every 5 s, full screen; q quits
alice@byteos ~> uptime                     # 14:03:12 up 2:05,  1 user,  4 processes
alice@byteos ~> uptime -p                  # up 2 hours, 5 minutes
alice@byteos ~> sleep 2m                   # wait (s, m, h); Ctrl+C ends it
```

`timeout` runs the command as a background process while it waits, so that
command cannot read the keyboard. `watch` needs quotes around pipes and `;`:
`watch -n 1 'ps | wc -l'`.
