# CCFE — The Curses Command Front-end

CCFE is a small Perl/curses tool that puts an interactive, screen-oriented
front-end on command-line scripts and commands: it prompts for the
information a command needs and can be driven by your shell to provide
predefined selections and run-time defaults.

Menus, forms and the commands they run are described in plain declarative
text files, so you can build a whole guided interface — and ship it as a
plugin — without writing any Perl.

The program source lives under [`src/`](src/); a mirror of the original
project website and its documentation is under `src/website-mirror/`, and
the manual pages are under `src/man/`.

## Status

`src/ccfe.pl` is the single-file program (currently version **1.60**). The
ongoing modernisation — packaging, security hardening, optional colour and a
move to a modular, more functional structure — is described in
[`REFACTOR.md`](REFACTOR.md). CCFE depends on **standard packages only**
(Perl core plus `libcurses-perl`); see the change log / git history for the
detail of past fixes.

## Dependencies

* `perl` — core modules only (POSIX, IPC::Open3, Getopt::Std,
  Text::Balanced, File::Temp, …).
* `libcurses-perl` — the `Curses` / ncurses + form + menu bindings.

On Debian/Ubuntu:

```sh
sudo apt-get install perl libcurses-perl
```

## Install

The installer templates the install paths into the program and installs the
bundled `sysmon` sample plugin into the demo menu:

```sh
cd src
sh install.sh                       # interactive; or:
sh install.sh -b -p "$HOME/.ccfe"   # batch install under ~/.ccfe
```

Add the install's `bin/` to your `PATH` (e.g. `export PATH="$HOME/.ccfe/bin:$PATH"`)
so you can just type `ccfe`.

## Running CCFE

CCFE takes an optional **shortcut** naming the menu or form to open. With no
argument it opens the program's default menu.

```sh
ccfe                 # default menu
ccfe demo            # the demo menu
ccfe sysmon          # the bundled sample-plugin menu
```

A shortcut can name a **form** as well as a menu, including one inside a
`.d/` form directory — handy for jumping straight to a single data-entry
screen or wiring CCFE into another script:

```sh
ccfe demo.d/recursive    # open a form directly
ccfe sysmon.d/sar        # the sysmon "system activity report" form
```

CCFE resolves a shortcut `<name>` by looking for `<name>.menu` then
`<name>.form` along its search path (see *Plugins* below). Run `ccfe` with no
argument, or consult `man ccfe`, to see what is available in an installation.

### One binary, many menu trees

CCFE keys its menu search path and config file off the **name it is invoked
as** (`basename($0)`). Symlink the binary to a new name and it becomes a
self-contained front-end with its own menus and its own `<name>.conf`:

```sh
ln -s "$HOME/.ccfe/bin/ccfe" "$HOME/.ccfe/bin/ops"
mkdir -p "$HOME/.ccfe/lib/ops"      # drop ops's *.menu / *.form here
ops                                 # runs the "ops" menu tree, reads ops.conf
```

This makes CCFE a natural way to give a team (or a constrained login) a
purpose-built menu without touching the default `ccfe` one.

## Docker

A minimal image (stock Debian + `libcurses-perl`) is provided:

```sh
docker build -t ccfe .
docker run -it ccfe          # opens the demo menu
docker run -it ccfe sysmon   # jump straight to a menu/form
```

## Plugins

CCFE is extended purely by dropping declarative files onto its **search
path**, which for a binary invoked as `ccfe` is:

1. `$LIBDIR/ccfe/`            — system-wide (e.g. `~/.ccfe/lib/ccfe/`)
2. `~/.ccfe/ccfe/`            — per-user overrides and additions

The building blocks:

| File | Purpose |
|---|---|
| `<name>.menu`            | a **static menu** — a list of items, each with an action |
| `<name>.menu/` directory | a **dynamic menu** — a `definition` file plus any number of `*.item` files merged into it |
| `<name>.form`            | a **form** — labelled fields the user fills in |
| `<name>.d/` directory    | a collection of related `.form` files |
| `*.item`                 | a single menu item a plugin drops into *another* menu's `.menu/` directory to graft itself on |

Items dispatch through action verbs — `menu:` (open another menu), `form:`
(open a form), `run:` (run a command in a pager-like view), `system:` (hand
the terminal to a full-screen command), and `exec:` (replace CCFE with the
command) — with modifiers like `(confirm,log,wait_key)`. Form fields can be
populated from a `list_cmd` (`command:` runs a program, `const:` is a fixed
list) so dropdowns can be driven by live data.

### Worked example — the `sysmon` plugin

`src/ccfe-plugin-sysmon/` is a complete, installable example. It ships:

* `sysmon.menu` — its top-level menu (`ps`, `top`, a `sar` form, …),
* `sysmon.d/*.form` — the forms those items open,
* `sysmon.item` — the one item that grafts `sysmon` onto the `demo` menu,
* its own `install.sh`.

Install it and run it:

```sh
cd src/ccfe-plugin-sysmon
sh install.sh
ccfe sysmon          # or pick "System resources..." from `ccfe demo`
```

### Writing your own

The quickest start is a per-user menu. Create `~/.ccfe/ccfe/mytools.menu`:

```
title { My tools }
item { id=DISK  descr=Disk usage          action=run:df -h }
item { id=LOGS  descr=Tail the syslog      action=run:tail -n 200 /var/log/syslog }
item { id=NET   descr=Network connections  action=run:ss -tunap }
```

then run `ccfe mytools`. See the manual pages under `src/man/` (or
`man ccfe`, `man ccfe-menu`, `man ccfe-form` after install) for the full
file-format reference, and `ccfe-plugin-sysmon` for forms and `list_cmd`
dropdowns.

## Tests

```sh
cd src
prove t/
```

The suite covers: that the program compiles; that the `.menu` / `.form` /
`.item` plugin file formats still parse against the demo and `sysmon`
fixtures; a source-level regression guard for the historical form crash; and
an end-to-end terminal smoke test that batch-installs CCFE into a temp prefix
and drives the menus and a form on a real pseudo-terminal. The parser tests
load the program headlessly (via the `CCFE_TESTING` guard) so no terminal is
required; the tty test brings its own pty (pure core Perl, see
`t/lib/CCFE/Test/Pty.pm`) and skips itself where no Linux pty / `Curses` is
available.
