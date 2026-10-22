# Contributing

ByteOS is open source, and changes are welcome: fixes, new commands, packages and
better documentation. This page is a short overview; the full guide is
[CONTRIBUTING.md](https://github.com/DevStarByte/ByteOS-OC/blob/master/CONTRIBUTING.md)
in the repository.

## The repository

| Branch | Holds |
|---|---|
| `master` | The operating system, the installer, the tools, the tests and these docs. |
| `packages` | The `pacman` repositories: package sources in `pkgs/<repo>/<name>/`, and the built packages and signed package lists GitHub makes from them. |

The `master` branch is laid out exactly like a ByteOS disk, so the repository folder
can be booted as one, for example in the [Ocelot Desktop](https://ocelot.fomalhaut.me/desktop/)
emulator.

!!! warning "master goes straight to players"
    `pacman -Syu` installs the newest commit on `master`. Everything pushed there
    reaches every ByteOS computer on its next upgrade, so keep `master` working and
    the tests green.

## Run the tests

The test suite boots the real kernel on a PC, with a fake screen, keyboard, disks,
network and internet card. You need Lua 5.3 or 5.4, `openssl` and a POSIX shell; no
Minecraft and no internet.

```sh
lua tools/test/run.lua            # everything
lua tools/test/run.lua shell      # only the cases whose name contains "shell"
lua tools/test/run.lua -v         # also list the tests that pass
```

On Windows, run them in WSL. To run the tests before every commit, turn on the
pre-commit hook once per clone:

```sh
git config core.hooksPath tools/hooks
```

GitHub also runs the tests with Lua 5.3 and 5.4 for every push and pull request.

## Writing code for ByteOS

- **Memory is scarce.** A computer may have only about 460 KiB. Put new things in a
  command (loaded only while it runs) or in a library that is loaded when needed;
  a test keeps the code that stays loaded at the prompt within a budget.
- **A command's manual page is the comment at the top of its program.** `man ls`
  shows the header of `bin/ls.lua`, and so does the [command reference](commands.md).
  Every command needs one.
- **Let the computer breathe.** OpenComputers stops a program that runs for
  seconds without waiting, so long loops call `k.event.pull(0)` now and then.
- Add tests for what you add or fix.

## Releases and packages

A ByteOS release sets the new version in `etc/os-release` and
`var/lib/pacman/local/byteos/desc`, lists new files in the base package's file list,
and gets a section in the
[changelog](https://github.com/DevStarByte/ByteOS-OC/blob/master/CHANGELOG.md).

A package is a folder with a `PKGBUILD.lua` and the files it installs (see
[Making packages](../packages/making.md)). Push it to `pkgs/core/` or `pkgs/extra/`
on the `packages` branch, and GitHub builds it, signs the package lists and publishes
them a minute later. The signing key is made with `tools/repokey.sh`; its private
half never goes into the repository.

## Improve these docs

The pages of this site are Markdown files in the `docs/` folder of the `master`
branch; the menu is in `mkdocs.yml`. Every page has an edit button (the pencil at the
top) that opens it on GitHub. To see your changes before you push them:

```sh
pip install mkdocs-material   # once
lua tools/gendocs.lua         # makes the command reference from the manual pages
mkdocs serve                  # the site at http://127.0.0.1:8000, updated as you save
```

The [command reference](commands.md) is not written by hand: `tools/gendocs.lua`
makes it from the commands' own manual pages, so to change a command's entry, change
the comment at the top of its program. When something in `docs/`, `mkdocs.yml` or the
commands changes on `master`, GitHub rebuilds the site and publishes it
(`.github/workflows/docs.yml`).
