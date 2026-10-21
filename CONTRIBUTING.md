# Contributing to ByteOS

This is for people changing ByteOS itself or its packages. Playing with
ByteOS in Minecraft is covered in the [README](README.md).

## The repository

| Branch | Holds |
|---|---|
| `master` | the OS: `init.lua boot/ sbin/ lib/ bin/ etc/ usr/share/man/ var/`, the installer, `tools/` |
| `packages` | the pacman repositories: sources in `pkgs/<repo>/<name>/`, built `.bpk` files and signed databases in `core/` and `extra/` |

The repository folder is laid out exactly like a ByteOS disk, so it can be
booted as one (see [Trying it](#trying-it)). Files keep `\n` line endings
everywhere, also in a Windows checkout (`.gitattributes` sees to it):
OpenComputers and the tests expect them.

## Running the tests

The test suite boots the real kernel on a PC: the repository folder becomes
the disk, with a fake screen, keyboard, network and internet card. It needs
**Lua 5.3 or 5.4**, `openssl` and a POSIX shell; no Minecraft, no internet.

```sh
lua tools/test/run.lua            # everything (about a minute)
lua tools/test/run.lua shell      # only cases whose name contains "shell"
lua tools/test/run.lua -v         # also list the tests that pass
```

Each case in `tools/test/cases/` runs in its own Lua process on a fresh
copy of the system. On Windows, run it in WSL (`wsl -e lua5.4
tools/test/run.lua`) or Git Bash with a Lua on the PATH.

GitHub runs the suite with Lua 5.3 and 5.4 for every push to `master` and
every pull request ([`.github/workflows/tests.yml`](.github/workflows/tests.yml)).

### The pre-commit hook

Turn it on once per clone, and every commit that touches the OS runs the
tests first:

```sh
git config core.hooksPath tools/hooks
```

It finds `lua`, `lua5.4` or `lua5.3`, also inside WSL. Commits that touch
only documents are let through without running the tests.
`git commit --no-verify` skips it, but CI still runs the tests.

## Writing code for ByteOS

- **Memory is the scarce thing.** A computer may have about 460 KiB. Only
  a few libraries stay loaded at the prompt, and `tools/test/cases/memory.lua`
  keeps their code within a budget. Put new things into a command (loaded
  only while it runs) or a library that is required when needed and let
  go of afterwards, as `lib/shellblocks.lua` and `lib/pacman/*` are. Avoid
  growing `lib/shell.lua`, `lib/term.lua`, `lib/tty.lua` and the kernel.
- **A command's man page is the comment at the top of its program**
  (`man ls` shows `bin/ls.lua`'s header). Every command in `/bin` needs a
  usable one; a test checks this. Topic pages live in `usr/share/man/`.
- **Let the machine breathe.** OpenComputers stops a computer that runs
  for seconds without waiting. Long loops call `k.event.pull(0)` now and
  then, which also lets Ctrl+C through.
- Commands get `arg`, `term`, `stdin`, `shell`, `fs` and `k` (the kernel).
  Read input with `stdin.read("a")` when no files are given, so the command
  works in a pipe. Turn paths into absolute ones with `shell.normalize`.
- Match the code around you: short comments that say why, plain English
  messages, `cmd: what went wrong` errors and exit codes like the GNU
  tools'.
- Add tests for what you add or fix, in the case it belongs to or a new
  one in `tools/test/cases/`.

## Releasing a version

`pacman -Syu` on a ByteOS computer installs the newest commit on `master`
(it compares commits, and shows the version as `X.Y.Z.g<commit>`). So
**everything pushed to `master` reaches players** on their next upgrade:
keep `master` working and the tests green. The version number is what
people see; a release is a commit that:

1. sets the new version in `etc/os-release` (`PRETTY_NAME`, `VERSION_ID`)
   and `var/lib/pacman/local/byteos/desc`; nothing else holds it
2. adds every new OS file to `var/lib/pacman/local/byteos/files` (sorted
   in byte order: `LC_ALL=C sort`); `pacman -Ql byteos` and `-Qo` use it
3. lists files that disappeared in `OBSOLETE` in `lib/sysupgrade.lua` if
   computers installed by copying files should lose them too
4. gets a section in [CHANGELOG.md](CHANGELOG.md)
5. is titled `ByteOS X.Y.Z: what changed`, with the details in the body

Use a minor version for new features and a patch version for fixes. Files
under `etc/` that users may edit are replaced on upgrade only when the
user left them alone; otherwise the new one is saved as `<file>.new`.

## Packages

A package is a directory with a `PKGBUILD.lua`, an optional install hook
and a `files/` tree laid out as on the disk; `man PKGBUILD` (or
[usr/share/man/PKGBUILD.txt](usr/share/man/PKGBUILD.txt)) describes the
format. Inside ByteOS, `makepkg <dir>` builds a `.bpk` and
`sudo pacman -U <file>.bpk` installs it.

To publish one, commit its directory to `pkgs/core/<name>/` or
`pkgs/extra/<name>/` on the `packages` branch and push. The *Build
packages* workflow on that branch builds every package with
`tools/mkrepo.lua` from `master`, signs the databases, checks the
signatures against `etc/pacman.d/byteos.pub` and commits the result. A
new version needs a higher `version` (or `rel` when only the packaging
changed).

Building by hand, in a checkout of the `packages` branch:

```sh
lua /path/to/master/tools/mkrepo.lua --key ~/.config/byteos/repo-key.pem .
```

mkrepo deletes `.bpk` files whose source is gone, but keeps the ones the
previous database listed for one more build, because GitHub's cache may
hand computers that database for a few minutes. So an old version (for
example `hyprbyte-1.3.1` next to `1.4.0`) stays until the next build after
an upgrade.

### The signing key

The package databases are signed with an ECDSA P-256 key; pacman checks
them against `etc/pacman.d/byteos.pub`. `tools/repokey.sh` makes a new key
pair: the private key goes to `~/.config/byteos/repo-key.pem` (never into
the repository, `*.pem` is ignored) and the public key to
`etc/pacman.d/byteos.pub`. For the workflow, store the private key as the
secret `REPO_KEY` (Settings → Secrets and variables → Actions). A new key
means a new `byteos.pub` on `master`, which computers get through
`pacman -Syu` before they can trust databases signed with it.

## Trying it

The [Ocelot Desktop](https://ocelot.fomalhaut.me/desktop/) emulator can
boot the repository folder as a computer's disk without Minecraft. On a
real OpenComputers computer, use the installer from the README.
