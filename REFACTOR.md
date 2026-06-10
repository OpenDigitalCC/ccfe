# CCFE — Modernisation Recommendations

**Subject:** `src/ccfe.pl` — single-file Perl/Curses TUI (≈4.6k lines).
**Date:** 2026-06-09 (recommendations refreshed after the v1.60 work).
**Goal:** keep CCFE on **standard packages only** (Perl core + `libcurses-perl`)
and the `.menu`/`.form`/`.item` plugin contract intact, while making it safer to
deploy, easier to maintain, and nicer to use.

---

## 1. Where things stand

**Already shipped in v1.60** (see the git log for the detail):

- The historical "segfault on forms"/startup crash is fixed — it was a Perl
  lifetime bug in how the menu/form item arrays were handed to ncurses, plus an
  empty-menu guard. No static recompilation was ever needed.
- The custom GCC/ncurses build apparatus was retired in favour of a slim
  Debian image; the runtime dependency is now just `perl` + `libcurses-perl`.
- A `Test::More` suite was added: compile check, plugin-format parser
  conformance, a source-level regression guard, and a pty-driven tty smoke
  test (`t/`), all core-only.

**Also now delivered** (post-v1.60 — see the git log and the section noted):

- **Security / restricted mode** (§2) — opt-in `restricted = yes` disables the
  F7 shell escape, the runnable-script save, and gates `system:`/`exec:` behind
  an allowlist; env hardening + `CCFE_FIELD_*` exposure are always on.
- **`lib/CCFE/` foundation** (§3) — the package tree exists; the security
  policy (`CCFE::Restrict`) and colour (`CCFE::Theme`) are extracted as pure,
  modern-Perl (`use v5.36`) modules, loaded via an `__FILE__`-relative
  `use lib`, shipped by the installer, and unit-tested. The legacy `require
  5.8.0` floor is gone.
- **Quality gates** (§4) — `.perlcriticrc`, `.perltidyrc`, a `Makefile`
  (`make check`) and a GitHub Actions CI workflow, enforced on the new modules.
- **Optional colour** (§5) — `CCFE::Theme` pre-creates the standard colour
  pairs so any `*_attr` can use `COLOR_PAIR(n)`; monochrome fallback intact.
- **`-k NAME` linter** (§6.4) — headless parse-check of a menu/form for authors
  and CI.

The test suite is now 105 tests (`make check`), still core + `libcurses-perl`
only. **What remains** is the bulk of the §3 de-globalisation of the legacy
single file, and the larger §6 items below (wide-char/UTF-8, full resize
reflow, runtime-config instead of `sed` templating, packaging).

CCFE's main program remains a single 4.6k-line script with no
`use strict`/`use warnings` and ~200 lines of global state; the parsing layer
(`load_menu`/`load_form`) is already curses-free, which is the seam the
remaining restructure builds on.

---

## 2. Security — preventing escape from the menu

CCFE is frequently deployed as a **constrained front-end**: a kiosk, an
operator console, or a restricted login (symlink the binary to a name and give
an account that menu tree as its shell). In that role the security goal is
simple — **a menu user must only be able to do what the menus allow** — but the
current code has several ways out. Treat **menu/form/config files as trusted**
(the administrator authors them) and **everything the end-user types as
untrusted**. The gaps below all break that boundary.

### 2.1 Escape vectors in the current code

| # | Vector | Where | Risk |
|---|--------|-------|------|
| E1 | **Shell-escape key (F7)** drops to a full interactive shell: `system("PS1=… $USER_SHELL")` | `call_shell` ≈`:659`, bound in `@MSKeys`/`@FSKeys`/`@RSKeys` | Total escape — the user gets a shell. Gated only by `valid_shell()`. |
| E2 | **Command injection via field values.** A field's value is substituted **raw** into a command string that is then run by `sh -c`: `$$action_ref =~ s/%\{$id\}/$val/g` then `open3(…, $OPEN3_SHELL, '-c', $cmd)` | subst ≈`:2842`; exec ≈`:510`,`:3956`; `system($cmd)` ≈`:674` | A field value of `; sh`, `$(…)`, or `` `…` `` runs arbitrary commands even inside an otherwise locked-down menu. |
| E3 | **`exec:` / `system:` verbs** run arbitrary commands by design; the final `exec($exec_args)` replaces CCFE with a shell-parsed string | `:4636`, dispatch in `do_menu`/`do_form` | Any menu/form that uses these (or a user-editable one) is an exit. |
| E4 | **Save-to-script** writes a runnable `#!$OPEN3_SHELL` script into `$HOME` | `:4225` | Combined with E1/E3, a way to stage and run code. |
| E5 | **Inherited environment / PATH.** `PATH` is rebuilt from `$MAIN_PATH:$PATH`; `IFS`, `LD_*`, etc. are inherited | `call_system` ≈`:670` | Untrusted env can redirect which binaries `run:`/`system:` resolve. |

### 2.2 Recommendations

1. **Add an explicit "restricted" policy (opt-in lockdown).** A single
   `RESTRICTED` switch in `.conf` (and/or keyed off the call-name, so a
   symlinked `kiosk` binary is locked while `ccfe` is not) that, when on:
   - removes `shell_escape` from `@MSKeys`/`@FSKeys`/`@RSKeys` (no F7),
   - disables `save`-to-script,
   - refuses the `exec:`/`system:` verbs unless the target is on an
     **allowlist**, and
   - optionally confines `run:` to an allowlisted set of commands.
   Centralise this in a `CCFE::Restrict` policy object consulted at every
   dispatch and key-handling site, so the rule lives in one place.

2. **Never interpolate untrusted input into a shell string (fixes E2).** Stop
   building `sh -c "$cmd"` out of `%{FIELD}` substitutions. Instead:
   - run actions with **`system`/`open3` LIST form** (`@argv`), so each field
     value is a distinct argument the shell never re-parses; or
   - export field values as **environment variables** (`CCFE_FIELD_<ID>`) that
     the command reads, rather than concatenating them into a command line.
   Where templating into a single string is genuinely required, **shell-quote
   by default** with a small core helper (single-quote + escape) — opt-out, not
   opt-in. This is the highest-value change: it closes injection even for menus
   that are *meant* to run commands.

3. **Harden the trusted edges.** Sanitise the environment before any exec
   (reset `IFS`, drop `LD_*`/`BASH_ENV`/`ENV`, set an absolute `PATH` from
   config), keep the existing `umask 0077`, and let the administrator **pin**
   `USER_SHELL`/`OPEN3_SHELL` in config and forbid user override (config
   precedence). Validate the shell against `/etc/shells` as well as
   `valid_shell()`.

4. **Audit trail.** In restricted mode, log every command actually executed
   (CCFE already has `trace()`; route it to an append-only, admin-owned file)
   so deployments have accountability for what ran.

5. **Make the trust boundary explicit in code and docs.** A short "Security &
   trust model" section in the man page and README: who may edit menus vs. who
   merely uses them, and the guarantee restricted mode does (and does not)
   provide. Add tests that assert F7/`exec:`/`save` are inert under
   `RESTRICTED=1`.

> These are defensive measures for operators who *want* to constrain a menu.
> They don't make CCFE a security boundary on their own (a determined local
> user has many avenues); pair restricted mode with OS-level controls
> (a real restricted shell, containerisation, or seccomp/AppArmor) for
> untrusted users.

---

## 3. Modular, more functional structure

The single file is the main maintainability cost. The target shape is the
**"functional core, imperative shell"** pattern: pure, terminal-free logic that
is trivial to unit-test, wrapped by a thin layer that does curses I/O and runs
commands.

### 3.1 Split into a package tree

`bin/ccfe` (thin entry point) + `lib/CCFE/`:

| Module | Responsibility | Purity |
|---|---|---|
| `CCFE::Config`  | `.conf` parsing, paths, constants, defaults | pure |
| `CCFE::MenuFile`| `.menu` / `.item` parsing (the `Text::Balanced` parser) | **pure** (already curses-free) |
| `CCFE::FormFile`| `.form` parsing | **pure** |
| `CCFE::Action`  | resolve `menu:`/`form:`/`run:`/`system:`/`exec:` + modifiers | pure |
| `CCFE::Layout`  | window geometry, pagination, column maths | **pure** (extract from `do_menu`/`do_form`) |
| `CCFE::Exec`    | `exec_command`/`call_system`/dispatch (the effectful edge) | effectful |
| `CCFE::Restrict`| the §2 security policy | pure decisions |
| `CCFE::Theme`   | attribute/colour mapping (the §5 colour work) | pure |
| `CCFE::UI::Menu`, `::Form`, `::List` | the curses widgets / event loops | effectful |

Keep the installer's path templating working (or, better, **drop the `sed`
templating** and read paths from config at runtime — see §6).

### 3.2 Make the core functional

- **Separate pure from effectful.** Parsing and action-resolution are already
  nearly pure (the headless parser tests prove it). Push the remaining global
  reads/writes out of them so `MenuFile`/`FormFile`/`Action`/`Layout` are
  referentially transparent and unit-testable with no terminal.
- **Return immutable data, don't mutate globals.** `load_menu` currently fills
  package globals (`%menu`, `@mf_path` side effects); have parsers *return* a
  data structure the caller owns.
- **Replace globals and `local` dynamic scope with an explicit `$ctx`.** The
  ~200 lines of globals (`:43-206`, `:4509-4545`) and the `local %form/@fp/…`
  threaded into nested subs (`do_form`) become one state object passed
  explicitly. This removes the spookiest action-at-a-distance in the code.
- **Pure layout helpers.** Pagination, scaling and column maths are inline in
  the event loops; extract them as pure functions and unit-test the edge cases
  (1-item menus, over-long labels, narrow terminals) that have historically
  bitten CCFE.
- **Thin event loops.** The `do_menu`/`do_form`/`do_list` loops become small
  imperative shells calling the pure helpers, which is also where `KEY_RESIZE`
  reflow (started in v1.60) belongs.

The `ccfe-plugin-sysmon` plugin is the **conformance fixture** throughout: the
restructure is "done" only when it installs and runs unchanged and the parser
tests still pass against it.

---

## 4. Automated quality gates

Add the standard Perl quality tooling (all available as Debian packages — no
CPAN required) and wire it into CI so regressions are caught mechanically.

1. **`use strict; use warnings;`** in every new module — the single biggest
   correctness win, and `perlcritic`'s first rule. Introduce per-module as the
   split in §3 lands (turning it on wholesale in the legacy file at once would
   bury you in fixups).
2. **`perlcritic`** (`libperl-critic-perl`). Add a `.perlcriticrc` that starts
   **lenient** and tightens over time:
   - enforce **strictly on `lib/CCFE/`** (target severity 3 "harsh", aiming for
     2),
   - exempt the legacy `ccfe.pl` initially (severity 5 "gentle") so it doesn't
     block work,
   so the new code is held to a high bar while the old code is migrated.
3. **`perltidy`** (`libperl-tidy-perl`) with a checked-in `.perltidyrc` for
   consistent formatting; add a `make tidy` / pre-commit check. The code is
   already fairly uniform, so this is low-friction.
4. **CI workflow** (GitHub Actions or equivalent) on Debian:
   `perl -c`, `prove -lr t/`, `perlcritic lib/`, `podchecker src/man/*`. The
   pty tty test skips itself in headless CI automatically, so the suite is
   green without a TTY.
5. **Coverage (optional):** `Devel::Cover` (`libdevel-cover-perl`) to track how
   much of the pure core the tests exercise — most useful once §3 makes the
   core testable.

### 4.1 Modern Perl idioms

The program was written for Perl 5.8 (the `require 5.8.0;` floor, now removed —
the runtime is Perl 5.40 on current Debian). New `lib/CCFE/` modules already
target modern Perl with `use v5.36` (which turns on `strict`, `warnings` and
subroutine **signatures** in one line). The legacy single file can adopt the
same idioms as it is de-globalised (§3); most are exactly what `perlcritic`
will flag:

| Modern feature | Replaces in CCFE | Note |
|---|---|---|
| `use v5.36` (strict+warnings+signatures+`say`) | no `strict`/`warnings`, `my ($a,$b)=@_;` in nearly every sub | the prerequisite; gate behind de-globalisation for `ccfe.pl` |
| Subroutine **signatures** `sub f ($a,$b)` | `@_` unpacking boilerplate | arity-checked, self-documenting |
| `//` and `//=` (defined-or) | `defined($x) ? $x : …` (e.g. `$ARGV[0] ? … : $REALNAME`, field defaults) | correct for `0`/`''` |
| `builtin::trim`, `true`/`false`, `is_bool` | the hand-rolled `trim()`, the `$YES`/`$NO` ints | core in 5.40 |
| `builtin::blessed` / `reftype`, the `isa` operator | the fragile `if ($item eq '')` allocation-failure checks on Curses objects | a real correctness fix |
| three-arg lexical `open(my $fh,'<',$f)` | two-arg bareword `open(INF,$f)` / `open(OUTF,">$fname")` | strict-clean and avoids mode-injection from odd filenames |
| `Cwd::getcwd` | backtick `` `pwd` `` (≈5 sites, incl. the `'pwd'` string typo) | no shell, faster |
| `system { $prog } @argv` / list-form exec | `system("$cmd")` / `open3(…, $SHELL,'-c',$cmd)` | no shell parsing — ties into the §2 injection work |
| postfix deref `$ref->@*`, `$ref->%*` | `@{ $menu{items} }`, `$#{ $form{fields} }` | readability |
| lexical subs `my sub` | nested named subs/closures (e.g. inside `do_form`) | tighter scope |

Apply opportunistically as each area is modularised; don't rewrite the legacy
file wholesale. `perlcritic` (§4.2) mechanically surfaces the two-arg opens,
bareword filehandles, string `eval`, and missing-`strict` cases.

---

## 5. Colour & theming

CCFE is **monochrome today**: it uses only attribute constants
(`A_NORMAL`/`A_REVERSE`/`A_BOLD`) and never calls `start_color()`. The good
news is that those attributes are already funnelled through **named variables**
(`$menu_fg_attr`, `$menu_bg_attr`, `$win_bg_attr`, `$RS_STDOUT_ATTR`,
`$RS_STDERR_ATTR`, `$RS_INFO_ATTR`, … around `:2471` and `:4556`), so colour is
a contained, additive change rather than a rewrite.

**How to add it:**

1. After `initscr`, guard on capability:
   `if (has_colors()) { start_color(); use_default_colors(); }`
   (`use_default_colors` lets `-1` mean "the terminal's own background", which
   looks right on themed terminals).
2. Define a small **palette of `COLOR_PAIR`s** for roles — title, menu item,
   selected item, footer/keys, field label, field value, info, stderr/error —
   with `init_pair($n, $fg, $bg)`.
3. Route the existing `*_attr` variables through `COLOR_PAIR($n)` (OR-able with
   `A_BOLD`/`A_REVERSE` for emphasis). Because they're already centralised,
   this is essentially one mapping table in `CCFE::Theme`.
4. Make the palette **configurable in `.conf`** (a `colors { title=cyan/-,
   selected=black/cyan, error=red/- }` block), so operators can theme a deployed
   menu without code changes.
5. **Fall back cleanly:** when `has_colors()` is false, in `$LAYOUT == $SIMPLE`,
   when `NO_COLOR` is set, or with a `--no-color` flag, keep today's monochrome
   attributes exactly. Colour must never be required.
6. The Debian build links `ncursesw`, so 256-colour and default-background are
   available; theming and a couple of shipped presets (e.g. "classic",
   "high-contrast") add real polish at low risk.

Keeping it gated and attribute-driven means monochrome terminals and the
existing SIMPLE layout are untouched.

---

## 6. Further value-adding recommendations

Beyond the above, ordered roughly by value-to-effort:

1. **Wide-char / UTF-8 correctness.** Width maths use byte `length()`/`substr()`
   (e.g. label/column truncation), which mis-aligns non-ASCII menus and forms.
   Move to display-column counting (core `Encode` + careful column logic, or a
   small width helper) now that `ncursesw` is the runtime. Important for
   internationalised menus and the existing `msg/` i18n.
2. **Finish resize reflow.** v1.60 made `KEY_RESIZE` trigger a redraw; complete
   it by tearing down and rebuilding windows from fresh `$LINES`/`$COLS` on
   `SIGWINCH`, so resizing reflows instead of just repainting the old geometry.
3. **Drop the `sed` path-templating; configure at runtime.** The installer
   rewrites `$LIBDIR`/`$MSGDIR`/… into the script. Reading those from config
   (with sane defaults relative to the binary) removes a fragile install step,
   makes the program runnable straight from the source tree, and simplifies
   packaging.
4. **A `ccfe --check <file>` linter and machine-readable `--dump`.** ✅ The
   linter shipped as `ccfe -k NAME` (parse-check, exit 0/1/2; see
   `t/07-check-cli.t`). Still open: a machine-readable `--dump` of the parsed
   structure (JSON/text) for tooling, docs generation and tests.
5. **Versioned plugin manifest.** A small `plugin.meta` declaring the CCFE
   version a plugin targets, so the loader can warn on mismatch — useful as the
   plugin surface evolves.
6. **Graceful in-curses errors.** Replace `fatal()`/`die`-to-raw-terminal with
   an in-curses error dialog plus a logged diagnostic, so a bad plugin doesn't
   dump a Perl stack over the screen.
7. **Proper packaging.** Ship a Debian package (`dh-make-perl`/`debhelper`) and
   a CPAN-style dist, so installation isn't a hand-rolled `install.sh`. Pairs
   naturally with §6.3.
8. **Mouse support (optional).** `Curses` exposes `mousemask`; clickable items
   and footer keys would modernise the UX without breaking keyboard use. Gate it
   behind config.
9. **Configurable keybindings & accessibility.** Keys are already partly
   configurable; expose them fully in `.conf`, and add a high-contrast theme
   (ties into §5) and a documented screen-reader-friendly mode.
10. **Docs refresh & a plugin tutorial.** Refresh the man pages, add a
    step-by-step "write your first plugin" guide, and document the §2 security
    model. Ship one extra `msg/` locale as a worked i18n example.

---

## 7. Suggested sequencing

The hotfix and tooling phases are **done** (v1.60). Remaining work, in
dependency order:

1. **Security (§2).** Field-value quoting/argv execution and restricted mode are
   high-value and can land on the current single-file program before the
   restructure. Add the inert-under-lockdown tests.
2. **Modularise (§3).** Split into `bin/` + `lib/CCFE/`, `strict`/`warnings`,
   de-globalise to a `$ctx`, extract the pure layout/parse core. Gate on the
   sysmon conformance test and the existing parser tests.
3. **Quality gates (§4).** Land `perlcritic`/`perltidy`/CI alongside the
   modular code so the new modules are held to standard from day one.
4. **Colour & UX (§5, §6).** Additive, lower-risk polish once the core is
   modular and tested: theming, wide-char correctness, resize reflow, the
   `--check`/`--dump` tooling, packaging.

**Net dependency throughout:** `perl` (core) + **`libcurses-perl`**. Nothing
else — the "standard packages only" constraint holds at every step.

---

## 8. Plugin system & file formats — preserve verbatim

The extension mechanism is the project's value and must survive every change
above unchanged. Contract to keep:

- **Discovery:** `ccfe <name>` resolves `<name>.menu` / `<name>.form` along the
  search path (`$LIBDIR/$CALLNAME`, `~/.ccfe/$CALLNAME`), keyed off the
  invoked name so symlinked front-ends get their own tree + `<name>.conf`.
- **Static menu** = a `.menu` file; **dynamic menu** = a `.menu` *directory* of
  `definition` + `*.item` files merged together.
- **Forms** = `.form` files, optionally grouped in a `.d` directory.
- **`.item` injection** — a plugin drops a `*.item` into another menu's
  directory to graft itself on (how `ccfe-plugin-sysmon` adds itself to `demo`).
- **Block syntax** via `Text::Balanced::extract_bracketed` — `title { }`,
  `top { }`, `item { id=… descr=… action=… }`, `field { … }`, `action { … }`.
- **Action verbs:** `menu:` / `form:` / `run:` / `system:` / `exec:` with
  modifiers `(confirm,log,wait_key)`.
- **`list_cmd`:** `command:single-val:…` / `command:multi-val:…` /
  `const:single-val:…` / `const:multi-val:…` with `%{FIELD_ID}` substitution
  (whose *execution* is hardened per §2.2, while the *syntax* is unchanged).

`ccfe-plugin-sysmon/` is the conformance fixture: any refactor is "done" only
when that plugin installs and runs unchanged.
