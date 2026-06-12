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

`src/ccfe.pl` is the program (currently version **2.3.1**). The ongoing
modernisation — packaging, security hardening, optional colour and a move to a
modular, more functional structure — is described in
[`REFACTOR.md`](REFACTOR.md) and [`ROADMAP.md`](ROADMAP.md). CCFE depends on
**standard packages only** (Perl core plus `libcurses-perl`); see the git
history for the detail of past fixes.

Recent work added things you drive **from inside the running UI**: a guided
config wizard, runtime config reload, colour-theme and key-map switching
(including Meta/Alt and Ctrl bindings), menu/form search, file-based
notifications, object-ownership management, and a one-step "run CCFE at login"
kiosk setup. These are covered below and in `man ccfe.conf`.

**v2.0 reorganises the install layout** (menus/forms moved out of `lib/` into
`share/ccfe/objects/`; per-user files follow the XDG base directories). See
[`MIGRATION.md`](MIGRATION.md) if you are upgrading from a 1.x install.

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
mkdir -p "$HOME/.local/share/ccfe/ops"   # drop ops's *.menu / *.form here
ops                                      # runs the "ops" tree, reads ops.conf
```

This makes CCFE a natural way to give a team (or a constrained login) a
purpose-built menu without touching the default `ccfe` one.

## Restricted mode

For constrained deployments (a kiosk, an operator console, a restricted
login), set `restricted = yes` in the `global { }` section of the config.
CCFE then disables the F7 shell escape and the runnable-script save, and
refuses the `system:` / `exec:` verbs unless the target program is on an
allowlist:

```
global {
  restricted       = yes
  restricted_allow = top, df, less
}
```

Field values are always exported to action commands as `CCFE_FIELD_<ID>`
environment variables, so menus can consume input safely (e.g.
`run:grep -- "$CCFE_FIELD_PATTERN" /var/log/syslog`) instead of interpolating
`%{PATTERN}` into a shell string.

**Deploying it as a boundary.** With `restricted = yes`, CCFE enforces the
policy so a logged-in user cannot step around it:

- `system:` / `exec:` are run **shell-free** (by argv), so the allowlist's
  program-name match actually holds — `system: df; sh` chaining and `%{FIELD}`
  metacharacters cannot reach a shell. `run:` stays the explicit "run a shell
  command" verb and is **not** allowlist-constrained, so don't expose `run:`
  actions in a restricted deployment you don't fully control.
- A config file the invoking user can **write** is ignored once restricted is
  on, so a system `/etc/ccfe.conf` that sets `restricted = yes` cannot be undone
  by `~/.config/ccfe`.
- Menu/form object directories the user can **write** are dropped from the
  search path, so a user cannot add their own menus.

For this to hold, deploy CCFE with **system-owned, user-unwritable** config and
object directories and run it as a **non-root** user (the usual restricted-login
setup). Defence in depth — OS-level confinement (a restricted shell, a
container, seccomp/AppArmor) — is still worthwhile for a true kiosk. See
`M8-AUDIT.md` and `TECH-DEBT.md` for the analysis and history.

`ccfe -R` (`--restricted`) forces restricted mode for a single run regardless of
config — it can only *tighten* (there is no flag to turn it off) and it also
makes the object search ignore user-writable directories. It's the primitive the
login-shell setup uses.

### Launching CCFE at login

**Configure CCFE → Login / shell setup** (the `ccfe-login` helper) makes CCFE
start automatically on an interactive login or SSH session — for the current
user, or **system-wide** via `/etc/profile.d` (which needs root). It hooks the
shell profile and fires on **interactive logins only**, so `scp`, `sftp`,
`rsync` and `ssh host command` are unaffected.

Tick **restricted kiosk mode** and the hook launches `ccfe -R` and replaces the
login shell with it, so the session is sandboxed and quitting the menu logs out:

```sh
ccfe-login install-user   -r      # kiosk menu for me on next login
ccfe-login install-system -r      # kiosk for every user (needs root)
ccfe-login status                 # what is enabled
ccfe-login uninstall-user         # undo
```

The block it writes is marker-delimited and idempotent, so it is safe to
re-apply or remove. A restricted CCFE session refuses these reconfiguration
commands, so a kiosk user can't unhook the login they're confined to.

## Colour and styles

CCFE is monochrome by default. When the terminal supports colour (and
`NO_COLOR` is unset and the layout is not `Simple`), it pre-creates the
standard foreground colour pairs, so any `*_attr` setting in the config may
reference `COLOR_PAIR(n)` — `1`=red, `2`=green, `3`=yellow, `4`=blue,
`5`=magenta, `6`=cyan, `7`=white — over the terminal's own background,
combinable with `A_BOLD` etc.

This themes the run-output (`browser_global`), the form fields (`field_attr`
/ `active_field_attr`), and the **menus** themselves (`menu_global`):

```
menu_global {
  screen_attr   = COLOR_PAIR(6)                       # menu text
  selected_attr = COLOR_PAIR(3) | A_REVERSE | A_BOLD  # highlight bar
  title_attr    = COLOR_PAIR(3) | A_BOLD              # header
  key_attr      = COLOR_PAIR(2) | A_REVERSE | A_BOLD  # control keys
}
browser_global {
  stderr_attr = COLOR_PAIR(1) | A_BOLD                # errors in red
}
```

`title_attr` (the header) and `key_attr` (the function-key bar) apply to every
screen — menus, forms and the output browser.

CCFE was modelled on AIX's SMIT, and ready-made themes ship under
`<prefix>/share/ccfe/themes/`: **`ccfe.conf.smit`** (the classic monochrome
original), **`ccfe.conf.smit-color`** (the colour version, including the header
and control keys), **`ccfe.conf.smit-panel`** (a panelled white-on-blue look)
and **`ccfe.conf.console`** (a Linux-console scheme). Drop one in as your
`ccfe.conf`, or use it as an instance config: symlink the binary to `smit` and
save it as `smit.conf`, so `smit` gets its own scheme and menu tree (see *One
binary, many menu trees* above).

You don't have to copy a theme by hand, though — **Configure CCFE → Select
colour theme** lists the installed themes and applies the chosen one at runtime
(next section).

## Configuring CCFE from the menu

Run **`ccfe config`** (or pick *Configure CCFE* from the default menu) for a
guided wizard that writes your personal `~/.config/ccfe/ccfe.conf` — screen
layout, behaviour toggles, shell/restricted mode, config variables — without an
editor. Several settings can then be changed **while CCFE is running** and take
effect immediately, no restart:

- **Reload** — *Apply configuration now* re-reads the config and re-applies
  colours, key bindings, behaviour toggles and variables. (Switching the mouse
  or the screen layout, and restricted mode, still need a restart; the
  confirmation says so.) Bind it to a key with `keymap { reload = ... }` for
  instant feedback while you tune a config.
- **Colour themes** — *Select colour theme* lists the themes installed under
  `share/ccfe/themes/`, saves your choice and applies it at once — the same as a
  `theme = NAME` line in the config.
- **Key maps** — *Select key map* switches between shipped presets:
  **classic** (the F1–F9 SMIT layout), **safe** (every function *also* on an
  Alt-letter, for terminals that grab the function keys), **nano** (Ctrl chords)
  and **mc**. Or spell your own out with a `keymap { }` section — each function
  can take an F-key, a Meta chord (`M-l`), a Ctrl chord (`^G`) or a plain key,
  primary plus alternates:

  ```
  keymap {
    list = F2, M-l
    back = F4, M-b, ^B
    exit = F9, M-q
  }
  ```

  (A lone `Esc` is still "cancel"; Meta chords are disambiguated by a short
  timeout — the `ESCDELAY` environment variable, default 25 ms.)
- **Search** — *Search menus and forms* (also on the main menu, or bind the
  `search` function to a key) scans every menu and form on the path — titles,
  top/bottom text, item descriptions and form field labels — and jumps to the
  match you pick.

**Notifications.** Point `notify_file` at a file and CCFE shows its contents as
a banner whenever a menu screen is entered (each distinct write once) — a simple
way for a producer to reach a logged-in operator.

## Docker

A minimal image (stock Debian + `libcurses-perl`) is provided:

```sh
docker build -t ccfe .
docker run -it ccfe          # opens the demo menu
docker run -it ccfe sysmon   # jump straight to a menu/form
```

### "Remembered commands" shell (compose)

`docker-compose.yml` turns CCFE into a throwaway shell of the admin/debug
commands you always forget — disk/memory/CPU, processes, networking, plus
parameterised *find* and *tail* forms and a Docker submenu:

```sh
docker compose run --rm ccfe          # open the remembered-commands menu
docker compose run --rm ccfe demo     # or jump to the bundled demo / sysmon
```

The curated objects live in `docker/objects/` and are bind-mounted read-only, so
you can edit the menu on the host without rebuilding (`ccfe -l` points at them).
The Docker items (`docker ps` / `images` / `logs`) need the host daemon — un-comment
the `docker.sock` mount in the compose file to enable them.

## Plugins

CCFE is extended purely by dropping declarative files onto its **search
path**, which for a binary invoked as `ccfe` is, in order:

1. `<prefix>/share/ccfe/objects/ccfe/`  — system-wide
2. `~/.local/share/ccfe/ccfe/`          — your XDG data dir
3. `~/.ccfe/ccfe/`                       — legacy fallback

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

The quickest start is a per-user menu. Create
`~/.local/share/ccfe/ccfe/mytools.menu`:

```
title { My tools }
item { id=DISK  descr=Disk usage          action=run:df -h }
item { id=LOGS  descr=Tail the syslog      action=run:tail -n 200 /var/log/syslog }
item { id=NET   descr=Network connections  action=run:ss -tunap }
```

then run `ccfe mytools`. See the manual pages under `src/man/` (or
`man ccfe`, `man ccfe_menu`, `man ccfe_form` after install) for the full
file-format reference, and `ccfe-plugin-sysmon` for forms and `list_cmd`
dropdowns.

### Build menus and forms without an editor

CCFE can build CCFE. Run `ccfe builder` for a guided menu that creates and
extends menus, forms and config — writing them to your XDG directory and
validating each with `ccfe -k`. It is plain CCFE content driving the
`ccfe-build` helper (the same helper is usable directly:
`ccfe-build new-menu mytools "My tools"`, `ccfe-build add-item mytools DISK
"Disk usage" "run:df -h"`). Field values reach the helper through
`$CCFE_FIELD_*`, so nothing you type is shell-interpolated.

The builder also manages **ownership** of your objects — *Change object
ownership* (`ccfe-build chown <name> <user>[:<group>]`) lists the local users
and groups to pick from and changes the owner of one of your own menus/forms.
Changing to another user usually needs root; if you lack the privilege the
error is shown plainly.

Validate a menu or form without opening the UI (useful for authors and CI):

```sh
ccfe -k mytools          # OK: menu "mytools" -- title "...", 3 item(s)
ccfe -k sysmon.d/sar     # checks a form; exits non-zero on a parse error
```

## Backing up & version-controlling your setup

Your CCFE setup is just text files: the config (`ccfe.conf`, plus any instance
`<name>.conf`) and your menus/forms. The system copies sit under your install
prefix; your **personal** additions follow the XDG base directories:

```
<prefix>/etc/ccfe.conf               system config
<prefix>/share/ccfe/objects/<name>/  system menus & forms
~/.config/ccfe/<name>.conf           your per-user config
~/.local/share/ccfe/<name>/          your per-user menus & forms
```

Because they're plain text, put them under version control — keep a small git
repo of just your config and menus so changes are reviewable and reversible:

```sh
mkdir -p ~/ccfe-config && cd ~/ccfe-config
git init
cp -r ~/.config/ccfe ./config        # your per-user config, if any
cp -r ~/.local/share/ccfe ./menus    # your per-user menus, if any
git add . && git commit -m "My CCFE config and menus"
```

To restore on a new machine, install CCFE (or the package), then copy these
files back into place. `ccfe -k <name>` parse-checks a menu/form after you
restore or edit it. (A guided config/backup workflow is a planned enhancement —
see `FEATURE-REQUESTS.md`.)

## Tests

```sh
cd src
prove t/
```

The suite (400+ tests) covers: that the program compiles; that the `.menu` /
`.form` / `.item` plugin file formats still parse against the demo and `sysmon`
fixtures; a source-level regression guard for the historical form crash; the
pure `CCFE::*` parser/layout/theme modules; and end-to-end terminal tests that
batch-install CCFE into a temp prefix and drive it on a real pseudo-terminal —
including the runtime reload, theme/key-map switching (and Meta-key bindings),
menu search, notifications, ownership and login-shell setup. The parser tests
load the program headlessly (via the `CCFE_TESTING` guard) so no terminal is
required; the tty tests bring their own pty (pure core Perl, see
`t/lib/CCFE/Test/Pty.pm`) and skip themselves where no Linux pty / `Curses` is
available.
