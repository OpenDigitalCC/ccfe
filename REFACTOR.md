# CCFE — Refactor Analysis & Recommendation

**Subject:** `src/ccfe.pl` (4593 lines, single-file Perl/Curses TUI, v1.58, 2009–2016)
**Issue:** [#1 — segfault on forms](https://github.com/OpusVL/perl-ccfe/issues/1)
**Date:** 2026-06-09
**Goal:** Bring CCFE up to modern Perl, fix the form/screen-drawing crashes, and
depend on **standard packages only** — while preserving the plugin system and the
`.menu` / `.form` / `.item` file formats.

---

## 1. Executive summary

CCFE is a single 4593-line Perl script with no `use strict`/`use warnings`, ~200
lines of global state, and `local`-based dynamic scoping. It drives a curses UI
through the **low-level `libform` / `libmenu` C bindings** of the `Curses` module.

The "segfault on forms" reported in issue #1 is **not** a defect in the `Curses`
module that requires static recompilation. It is a pair of concrete, reproducible
**Perl logic bugs**, both fixed in v1.60:

1. **Dangling items/fields buffer (the primary crash).** `new_menu()` and
   `new_form()` store the caller's packed `ITEM**` / `FIELD**` array pointer
   **without copying it** — the array must stay valid for the entire life of the
   menu/form (that is how the underlying ncurses `libmenu`/`libform` work). CCFE
   built the array inline as `new_menu( pack 'L!*', @fset )`, so the packed string
   was a Perl **temporary that was freed/reused the moment the statement ended**,
   leaving ncurses holding a dangling pointer. With ≥ 3 items the freed buffer
   happened to survive long enough to limp along; with **1–2 items** (the `demo`
   and `ccfe` install menus, and every short form) the memory was reused
   immediately and the first menu/form operation dereferenced freed memory — a
   hard **SIGSEGV before a single character was painted**. This is why the demo
   menu crashed on startup and forms "segfaulted". Fixed by holding the packed
   buffer in a lexical that outlives the menu/form at all four call sites.

2. **`item_index(NULL)` on an empty menu.** Separately, a curses menu built from an
   **empty item list** then calls `item_index(current_item($cmenu))`; `current_item`
   returns NULL and `item_index(NULL)` produces exactly the reported error —

   > `argument 0 to Curses function 'item_index' is not a Curses item at … line 2539`

   — which, depending on the ncurses build, surfaces as a Perl die or a hard
   segfault. Fixed by an empty-list guard plus a NULL-current-item guard.

**Therefore the entire custom Docker toolchain (custom GCC + binutils + statically
compiled ncurses) built to "fix" this is the wrong remedy and should be retired.**
The fix is in the Perl. The runtime dependency reduces to a **single standard Debian
package**: `libcurses-perl`. Everything else CCFE uses is in the Perl core.

Recommended path: a **staged in-place modernisation** (not a rewrite-from-scratch),
keeping the `Curses` module for raw window drawing/input but **hardening or replacing
the fragile `libform`/`libmenu` usage** that is the actual crash surface, plus the
standard modernisation hygiene (strict/warnings, packaging, tests). The plugin and
file-format contract is preserved verbatim for backward compatibility.

---

## 2. Root cause of issue #1 (the crash)

### 2.0 The primary crash: a dangling items/fields buffer

All four menu/form constructions used the same idiom:

```perl
$cmenu = new_menu( pack 'L!*', @fset );   # do_menu:2133, do_list:2491
$cform = new_form( pack 'L!*', @fset );   # ask_string:831, do_form:3230
```

`new_menu()`/`new_form()` keep the **pointer** to that packed array; ncurses does
**not** copy it. The `pack 'L!*', @fset` expression is an anonymous temporary, so
Perl is free to reclaim its buffer as soon as the statement completes — after which
ncurses is dereferencing freed memory on every subsequent menu/form call.

Whether it crashes is pure allocation luck: with ≥ 3 items the buffer survived long
enough to work; with 1 or 2 items the freed memory was reused immediately and the
**first** operation (`set_menu_mark`, `set_menu_format`, …) segfaulted, before any
output was painted. That is exactly the demo (1 item) and ccfe (2 item) menus, and
every short form — so the program crashed on its very first screen. Confirmed with a
minimal pure-`Curses` reproducer (1–2 items crash, 3+ survive) and pinned by the
pty-driven `t/03-tty-smoke.t`.

**Fix:** keep the packed buffer in a lexical that lives until `free_menu`/`free_form`:

```perl
my $items_buf = pack 'L!*', @fset;   # MUST outlive the menu/form
$cmenu = new_menu($items_buf);
```

### 2.1 The secondary crash site (empty list)

`src/ccfe.pl:2541` (inside `do_list`):

```perl
$pos_msg = sprintf( "  %s%d/%d%s%s",
    $lflag, item_index( current_item($cmenu) ) + 1,   # <-- line 2541
    item_count($cmenu), ... );
```

If `$cmenu` has **no items**, `current_item($cmenu)` is NULL, and `item_index(NULL)`
throws/segfaults. The menu is built a few lines earlier from `@fset`:

```perl
# src/ccfe.pl:2450-2475
foreach $i ( 0 .. $#$ilist_ref ) { ... push @fset, ${$item}; }
push @fset, 0;
$cmenu = new_menu( pack 'L!*', @fset );   # empty when $ilist_ref is empty
```

When `$ilist_ref` is empty, `@fset` is just the terminating `0`, the menu has zero
items, and line 2541 detonates.

### 2.2 How an empty list reaches `do_list`

`do_form` guards the **normal** select path against an empty list
(`src/ccfe.pl:3585` `if (@list) { … do_list(…) }`), but the **error** path does not:

```perl
# src/ccfe.pl:3565-3574
unless ( exec_command( $args, $form{path}, \@list, \@err ) ) {
    ...
    ($es) = do_list( $win, 'Error', 'display', \@err, undef );  # @err may be EMPTY
    @list = ();
}
```

When a field's `list_cmd` (`command:single-val:…`) exits non-zero **but writes
nothing to stderr**, `@err` is empty, yet `do_list` is still invoked to "show the
error" — building a zero-item menu and crashing at line 2541.

This precisely explains every symptom in the issue:

| Issue symptom | Explanation |
|---|---|
| "dropdowns sometimes fail to populate" | the `list_cmd` command failed / produced no rows |
| "F2/F5 on select fields frequently cause crashes" | F2 = `list`, which runs the list_cmd path above |
| "behaviour varies across systems" | whether a failing command emits stderr depends on locale / coreutils version — so `@err` is empty on some boxes and not others |
| `item_index … is not a Curses item` | `current_item` of an empty menu is NULL |

### 2.3 Secondary fragilities on the same surface

These don't all crash today but are the same class of "low-level binding misuse"
and should be cleaned up together:

- **Pointer packing.** `new_menu( pack 'L!*', @fset )` / `new_form( pack 'L!*', @fset )`
  hand-pack C pointers as `unsigned long`. Correct on LP64 Linux, but brittle and
  the root reason the project feared a "needs static compilation" problem.
- **Truthiness checks.** `if ( $item eq '' )` (`:2465`) and `if ( $cmenu eq '' )`
  (`:2476`) string-compare what are really blessed/undef values; they do not reliably
  detect allocation failure.
- **No empty-menu guard** anywhere `current_item`/`item_index` are called
  (`:2166`, `:2211`, `:2541`, `:2606`, `:2626`).
- **No `KEY_RESIZE` / SIGWINCH handling.** `$LINES`/`$COLS` are read once at
  `initscr` (`:4477`) and never refreshed; resizing the terminal corrupts the
  drawing. This is the "screen drawing" half of the report.

### 2.4 Minimal hotfix (independent of the full refactor)

Two small changes stop the crash immediately and can ship before any restructuring:

1. In `do_list`, return early when the item list is empty (show a message via
   `disp_msg` instead of building a menu); never call `item_index`/`current_item`
   on a zero-item menu.
2. In `do_form`'s error branch (`:3571`), only call `do_list` when `@err` is
   non-empty; otherwise use `disp_msg` with a generic "command failed" message.

---

## 3. Dependency analysis — "standard packages only"

Every `use`/`require` in `ccfe.pl:23-37`:

| Module | Source | Debian package | Action |
|---|---|---|---|
| `Curses` | XS / ncurses | **`libcurses-perl`** | **only non-core runtime dep — keep** |
| `Sys::Hostname` | core | (perl) | keep |
| `File::Basename` | core | (perl) | keep |
| `POSIX` | core | (perl) | keep |
| `Getopt::Std` | core | (perl) | keep |
| `IPC::Open3` | core | (perl) | keep |
| `Symbol` | core | (perl) | keep |
| `IO::File` | core | (perl) | keep |
| `Term::ANSIColor` | core | (perl) | keep (barely used; candidate to drop) |
| `Text::Balanced` | core | (perl) | keep (the `.menu`/`.form` parser) |
| `IO::Select` | core | (perl) | **imported but unused — drop** |
| `File::Temp` | core | (perl) | keep |
| `Digest::MD5` | core | (perl) | **effectively unused — drop** |

**Conclusion:** the complete dependency footprint is **`libcurses-perl` plus the
Perl core** (shipped by `perl` / `perl-modules-5.NN`). That already satisfies
"standard packages only" — no CPAN-only modules, no custom-built libraries.

`libcurses-perl` on current Debian (trixie) is built against the system
`libncursesw6` (6.5) and provides the `Curses`, form, menu and panel bindings CCFE
needs. It is **not currently installed on this host** — installing it requires apt:

> **Action for the user:** `sudo apt-get install libcurses-perl`
> (needed to run/test CCFE at all; Claude cannot install it — no sudo on this host.)

For building a `.deb` and tests (dev-time only, all standard Debian):
`dh-make-perl` / `debhelper`, `libtest-simple-perl` (core), optionally `perltidy`
and `libperl-critic-perl`.

### 3.1 Retire the custom toolchain

`Dockerfile` / `Dockerfile.initial` build a bespoke GCC 7.5 + binutils + mpc +
2020-era Perl + statically compiled ncurses, purely to chase the segfault via static
linking. Since the crash is a Perl logic bug (§2), this apparatus is unnecessary and
a maintenance liability. Replace it (if a container is still wanted) with a trivial:

```dockerfile
FROM debian:stable-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        perl libcurses-perl ncurses-base ncurses-term && \
    rm -rf /var/lib/apt/lists/*
COPY src/ /opt/ccfe/
ENTRYPOINT ["/opt/ccfe/ccfe"]
```

Keep the old Dockerfiles in git history; remove them from the working tree.

---

## 4. Code-quality findings (modernisation targets)

| # | Finding | Location | Recommendation |
|---|---|---|---|
| 1 | No `use strict` / `use warnings` | top of file | add both; fix the fallout incrementally per package |
| 2 | ~200 lines of unscoped globals | `:43-206`, `:4509-4545` | move into a config object / `Readonly`-style constants block |
| 3 | `local @fp/$cform/%form/%field_vals` dynamic scope shared into nested subs | `do_form` `:2658-` | make these explicit state passed as a `$ctx` hashref |
| 4 | Shell-string command execution | `exec_command` `:482`, `call_system` `:662`, `exec($exec_args)` `:4578` | document trust model; prefer `system LIST` / `open3 LIST` where the action is a single program; field-value substitution into `list_cmd` is unescaped (`:3558`) — quote or pass via env |
| 5 | Typo: `'pwd'` string instead of `` `pwd` `` | `:650` | fix or replace with `Cwd::getcwd` (core) |
| 6 | No terminal-resize handling | event loops in `do_menu`/`do_form`/`do_list` | handle `KEY_RESIZE`: tear down + rebuild windows from fresh `$LINES`/`$COLS` |
| 7 | Fragile `pack 'L!*'` pointer arrays | `:2131`,`:2475`,`:3209` | encapsulate in one helper; long-term, replace libform/libmenu (see §5 Option B) |
| 8 | Zero automated tests | — | add parser + smoke tests (§6) |

None of the above changes the on-disk `.menu`/`.form`/`.item` formats.

---

## 5. Recommended refactor strategy

Two viable shapes. **Recommendation: Option A now, with Option B as an optional
later phase** — A fixes the crash and modernises with the least risk to existing
plugins; B removes the fragile C-binding surface entirely if the project wants to
fully de-risk the menu/form layer.

### Option A — Modernise in place, keep `Curses`, harden the bindings  ✅ recommended

Smallest blast radius, preserves behaviour and plugins exactly.

1. **Package the program.** Split `ccfe.pl` into a thin `bin/ccfe` plus
   `lib/CCFE/*.pm` modules along the existing seams the analysis already found:
   - `CCFE::Config`   — config/`.conf` parsing, paths, constants
   - `CCFE::MenuFile` — `.menu` / `.item` parsing (the `Text::Balanced` parser)
   - `CCFE::FormFile` — `.form` parsing
   - `CCFE::UI::Menu`, `CCFE::UI::Form`, `CCFE::UI::List` — the curses widgets
   - `CCFE::Exec`     — `exec_command` / `call_system` / action dispatch
   - `CCFE::Action`   — the `menu:` / `form:` / `run:` / `system:` / `exec:` dispatcher
   Keep the installer's `sed`-based path templating working, or replace it with a
   config file read at runtime.
2. `use strict; use warnings;` per module; convert globals to `my`/state passed in
   a context object; keep a compatibility shim for the handful of values the
   installer rewrites.
3. **Fix the crash (§2.4)** and add a single guarded accessor used everywhere:
   `current_index($menu)` returns `undef` (not a die) on an empty menu.
4. Wrap the pointer packing in one `_pack_ptrs(@objs)` helper so the `L!*` assumption
   lives in exactly one place.
5. Add `KEY_RESIZE` handling to the three event loops.
6. Replace the custom Docker toolchain with the slim image (§3.1).

### Option B — Replace `libform`/`libmenu` with hand-rolled widgets (optional, later)

Keep `Curses` only for raw windows, input, and attributes; reimplement the menu,
list and form widgets in plain Perl (a scrollable list with a cursor index, fields
as `(label,value,type)` structs you draw and edit yourself). This **eliminates the
entire unsafe C-binding surface** that issue #1 lives on, still depends on nothing
beyond `libcurses-perl`, and gives full control over resize and edge cases. More
work, but it permanently removes the segfault class. Do this only after Option A
ships and is stable.

> Not recommended: migrating to `Curses::UI`. It also depends on `Curses`, is itself
> lightly maintained, and would force a rewrite of the rendering without removing the
> underlying binding risk — no net dependency or safety win.

---

## 6. Plugin system & file formats — preserve verbatim

The extension mechanism is the project's value and must survive the refactor
unchanged. Contract to keep:

- **Discovery:** `ccfe <name>` resolves `<name>.menu` / `<name>.form` along
  `@mf_path` = `$LIBDIR/$CALLNAME`, `~/.ccfe/$CALLNAME` (`:169`).
- **Static menu** = a `.menu` file; **dynamic menu** = a `.menu` *directory* of
  `definition` + `*.item` files, globbed at `:959`.
- **Forms** = `.form` files, optionally grouped in a `.d` directory.
- **`.item` injection** — a plugin drops a `*.item` into another menu's directory
  (how `ccfe-plugin-sysmon` adds itself to `demo.menu`).
- **Block syntax** parsed via `Text::Balanced::extract_bracketed` — `title { }`,
  `top { }`, `item { id=… descr=… action=… }`, `field { … }`, `action { … }`.
- **Action verbs:** `menu:` / `form:` / `run:` / `system:` / `exec:` with
  modifiers `(confirm,log,wait_key)`.
- **`list_cmd`:** `command:single-val:…` / `command:multi-val:…` /
  `const:single-val:…` / `const:multi-val:…`, with `%{FIELD_ID}` substitution.

`ccfe-plugin-sysmon/` (its `install.sh`, `sysmon.item`, `sysmon.menu`, `sysmon.d/`)
becomes the **conformance fixture**: the refactor is "done" when that plugin installs
and runs unchanged.

### Suggested tests (all `Test::More`, core)

1. **Parser tests** — feed the demo/sysmon `.menu`/`.form`/`.item` files to the
   parser modules, assert the resulting data structures (no curses needed).
2. **Regression test for #1** — a `list_cmd` whose command exits non-zero with empty
   stderr must show a message, not build a zero-item menu / die.
3. **Smoke test** — `ccfe -h` / `ccfe -c` exit 0 and print expected keys.
4. **Plugin conformance** — install `ccfe-plugin-sysmon` into a temp prefix and
   assert menu/form resolution.

---

## 7. Phased plan

1. **Phase 0 — Hotfix (½ day):** apply §2.4; add the empty-menu guard and the
   resize handler. Ship; closes issue #1.
2. **Phase 1 — Tooling (½ day):** slim Dockerfile (§3.1); remove custom toolchain
   from the tree; add `Test::More` harness + parser/regression tests; document
   `apt-get install libcurses-perl`.
3. **Phase 2 — Modularise (Option A):** split into `bin/` + `lib/CCFE/`,
   `strict`/`warnings`, de-globalise, one pointer-packing helper. Keep formats and
   the installer working; gate on the sysmon conformance test.
4. **Phase 3 — Harden exec & docs:** safer command execution, escape `list_cmd`
   substitutions, refresh the man pages.
5. **Phase 4 (optional) — Option B:** retire `libform`/`libmenu` for hand-rolled
   widgets to remove the segfault class permanently.

**Net dependency after refactor:** `perl` (core) + **`libcurses-perl`**. Nothing else.
