# CCFE — The Curses Command Front-end

CCFE is a small Perl/curses tool that puts an interactive, screen-oriented
front-end on command-line scripts and commands: it prompts for the
information a command needs and can be driven by your shell to provide
predefined selections and run-time defaults.

This repository is the OpusVL continuation of Massimo Loschi's original
CCFE (the original author is not contactable). The program source lives
under [`src/`](src/); a mirror of the original project website and its
documentation is under `src/website-mirror/`.

## Status

`src/ccfe.pl` is the original single-file program. Version **1.60** fixes
[issue #1 — "segfault on forms"](https://github.com/OpusVL/perl-ccfe/issues/1)
and begins the modernisation described in [`REFACTOR.md`](REFACTOR.md).

The segfault was **not** a defect in the `Curses` module that needed a
statically compiled ncurses (which is what the old build tooling tried to
provide). It was a logic bug: a curses menu was built from an empty item
list, after which `item_index(current_item(...))` dereferenced a NULL item.
That is fixed, so CCFE now depends on **standard packages only**.

## Dependencies

* `perl` — core modules only (POSIX, IPC::Open3, Getopt::Std,
  Text::Balanced, File::Temp, …).
* `libcurses-perl` — the `Curses` / ncurses + form + menu bindings.

On Debian/Ubuntu:

```sh
sudo apt-get install perl libcurses-perl
```

## Install

The upstream installer templates the install paths into the program and
installs the bundled `sysmon` sample plugin into the demo menu:

```sh
cd src
sh install.sh            # interactive; or:
sh install.sh -b -p "$HOME/.ccfe"   # batch install under ~/.ccfe
```

Then run the demo:

```sh
"$HOME/.ccfe/bin/ccfe" demo
```

## Docker

A minimal image (stock Debian + `libcurses-perl`) is provided:

```sh
docker build -t ccfe .
docker run -it ccfe          # opens the demo menu
docker run -it ccfe sysmon   # jump straight to a menu/form
```

## Tests

```sh
cd src
prove t/
```

The suite covers: that the program compiles (`t/00-compile.t`); that the
`.menu` / `.form` / `.item` plugin file formats still parse against the
demo and `sysmon` fixtures (`t/01-parsers.t`); and a regression guard for
issue #1 (`t/02-issue1-regression.t`). The parser tests load the program
headlessly via the `CCFE_TESTING` guard, so no terminal is required.

## Plugins

CCFE is extended by dropping declarative files onto its search path:
`.menu` files (or `.menu/` directories of `definition` + `*.item` files),
`.form` files, and `.d/` form collections, dispatched through
`menu:` / `form:` / `run:` / `system:` / `exec:` actions. See
`src/ccfe-plugin-sysmon/` for a worked example and the manual pages under
`src/man/` for the file formats.
