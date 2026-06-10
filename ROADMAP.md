# CCFE Roadmap

Consolidates the outstanding [`REFACTOR.md`](REFACTOR.md) items and the
[`FEATURE-REQUESTS.md`](FEATURE-REQUESTS.md) backlog into a single sequence.

**Principles:** standard Debian packages only; the `.menu`/`.form`/`.item`
plugin contract is preserved; every step keeps `make check` green; work lands
in small, reviewable commits.

**Ordering rationale:** features and the layout change come first; the large
internal **de-globalisation is deferred to the end (M7)** so it is done once,
against settled feature code, instead of being re-run as later milestones move
things around. The **non-functional audit (M8) is the final gate.**

| # | Milestone | Effort | Risk | Depends on |
|---|-----------|--------|------|------------|
| M0 | Housekeeping | S | low | — |
| M1 | Reorganise the layout → **cut v2.0** | M | med | — |
| M2 | Runtime configuration (drop `sed` templating) | M | med | M1 |
| M3 | Packaging (deb → rpm → alpine) | M/distro | low–med | M1, M2 |
| M4 | Multi-page forms | M–L | med–high | — |
| M5 | Guided builders (form builder + config walkthrough) | L | med | M1 |
| M6 | UX & quality polish | M | low–med | — |
| M7 | De-globalisation / full modularisation | L | med | M1–M6 |
| M8 | Non-functional close-out audit | S–M | low | all |

---

## M0 — Housekeeping  · _independent, do first_
- Add a top-level `LICENSE` (GPL-2.0, surfacing `src/COPYING`). _[req: Licence]_
- Adopt git history as the changelog: replace the maintained `ChangeLog`
  with a pointer to `git log` / generated notes. _[req: Changelog]_
- README: a short "**backing up & version-controlling your config and
  menus**" section, and confirm the "selecting colour/themes" docs. _[req: Reorganise]_

## M1 — Reorganise the layout  · **breaking → cut v2.0**
The user-flagged confusion: `lib/` holds both Perl modules and menus. Move to
a layout where each thing has one obvious home:

```
bin/ccfe (+ smit symlink)        the program
lib/perl5/CCFE/*.pm              internal Perl modules
share/ccfe/objects/<app>/        menus & forms   (OUT of lib/)
share/ccfe/themes/*.conf         shipped themes (smit, smit-color, console)
etc/ccfe/ccfe.conf               config
share/{doc,man}/ccfe, msg/, var/log/ccfe
~/.ccfe/  (keep; optionally XDG ~/.config + ~/.local/share with fallback)
```
Update `install.sh`, the `@mf_path`/`@cnf_path` defaults and the docs; keep the
call-name instance mechanism. Ship a migration note. _[req: Reorganise]_

## M2 — Runtime configuration
Drop the `sed` path-templating (REFACTOR §6.3): compute paths relative to the
binary / read from config, so CCFE runs straight from a checkout and from any
prefix. Prerequisite for clean distro packages.

## M3 — Packaging  _[req: Packages; REFACTOR §6.7]_
`.deb` (debhelper) first, then `.rpm` (RHEL/clones spec), then Alpine
`APKBUILD`. CI builds the artifacts.

## M4 — Multi-page forms  _[req: Multi-page forms]_
Paginate long forms in `do_form` (page N/M, navigation, field grouping).
UI-heavy → pty tests. (Easier after M7, but can proceed independently.)

## M5 — Guided builders  _[req: Form builder + ccfe config walkthrough]_
"CCFE building CCFE": menus/forms that walk a user through creating/installing
a menu or form and editing `ccfe.conf`, setting permissions — implemented
mostly as CCFE content (dogfooding) plus a small backend that validates (reuse
`-k`), writes to the M1 location, and sets perms.

## M6 — UX & quality polish  _(REFACTOR §5/§6, interleave)_
Full fg/bg colour **palette** section (background colours / panelled SMIT
look), wide-char/UTF-8 correctness, machine-readable `--dump`, graceful
in-curses errors, mouse, plugin manifest.

✅ **Resize reflow** (done): `do_menu` rebuilds its windows/menu and `do_form`
re-paginates its fields and rebuilds its window on `KEY_RESIZE` (values
preserved); builds clamped to 80x24 (no crash on a tiny terminal) and an
`END{}` restores the terminal on any die. `t/10-resize.t`. A narrow resize used
to crash a form (value fields are right-aligned to the launch width → once the
terminal is narrower than the value column, `post_form` returned `E_NO_ROOM`,
the form was left unposted and the loop faulted, surfacing as exit 245);
`do_form` now widens the rebuilt window to hold every field so `post_form`
always succeeds.

✅ **Value column + label wrap** (done): values are right-aligned to the screen
edge (classic SMIT), so they expand to use the width of a wide terminal; when a
label is too long to leave `$FIELD_VALUE_GAP` columns before that value (a long
label on a narrow terminal) the label wraps onto its own line(s) and the value
drops to the row below, so it is never pushed off-screen or truncated.
`t/11-layout.t`.

✅ **Horizontal re-flow on resize** (done): `resize_form` re-right-aligns the
value column and re-wraps long labels to the new width (not just the vertical
re-pagination), recreating the two width-dependent fields (label, dot run) and
moving the rest, so values track the terminal's right edge and stay on-screen
as it grows or shrinks. `t/11-layout.t`.

✅ **Pop-up resize + graceful errors** (done): `do_list` re-centres for the new
size and `run_browse` rebuilds its full-screen frame/viewport on `KEY_RESIZE`
(both clamped, no crash); and the top-level interaction runs under a guard that,
on any uncaught die from a menu/form, restores the terminal and prints a clean
one-line message instead of a Perl backtrace on a curses screen. Open for these
pop-ups: re-wrapping their *content* to the new width, and propagating the
resize to the menu/form underneath (it does not see the event while a pop-up is
open); word-boundary (vs character) label wrapping.

✅ **Wide-char / UTF-8 layout** (done): `setlocale(LC_CTYPE)` is adopted so
ncursesw renders multi-byte text by display column, and a `disp_width()` helper
(ASCII fast-path → `Text::CharWidth::mbswidth`, falling back to `length()` if
the module is absent — added as a Debian `Recommends`) replaces byte-count
`length()` in the layout maths (labels, titles, message/popup centring), so an
accented or CJK label lays out by the columns it occupies, not its byte count.
`t/11-layout.t`. Open: column-aware *truncation* of over-long messages
(`substr` still cuts by byte), and multi-byte field **input** (the byte-only
Perl Curses API makes typing non-ASCII into a field hard).

✅ **Full fg/bg colour palette** (done): beyond the seven standard
foreground-over-default pairs, a theme can now request any foreground-over-
background pair with `color_pair('white','blue')` in a `*_attr` value.
`CCFE::Theme::pair_for()` reserves a pair number at config-eval time (before
`start_color()`) and `init_dynamic_pairs()` creates them once colour is up; the
screen background (`screen_attr`) is applied to menus, forms **and** the output
browser, giving the panelled SMIT look (e.g. white-on-blue). Ships as
`ccfe.conf.smit-panel`; `t/06-color.t` covers the allocator and that a
`color_pair()` background actually paints. Open: a 256-colour / true-colour
palette, and per-instance theme selection without copying a config.

✅ **Machine-readable `--dump`** (done): `ccfe --dump NAME` (or `-D NAME`)
parses a menu or form with the headless parser and prints it as JSON on stdout
— menu items (id/descr/action) or form fields (id, label, type name, len,
required, default, list_cmd) plus the title/top/action — then exits (0 ok, 1
parse error, 2 not found), like `-k`.  For scripting, automation and the audit.
`t/07-check-cli.t`.

✅ **Mouse** (done, opt-in): with `mouse = YES` in the config, `do_menu` grabs
left clicks — a single click moves the selection to the clicked item, a double
click activates it (re-dispatched as Enter).  Off by default so the terminal's
own click-to-select text keeps working.  Uses `mousemask` + the packed `MEVENT`
from `getmouse`.  `t/12-mouse.t`.  Open: clickable footer function-keys, and
mouse in forms / the pop-up list / the output browser.

✅ **Plugin manifest** (done): a plugin can ship a `<name>.plugin` manifest (a
`plugin { name/version/description/author/provides/requires }` block) beside its
menu; `ccfe --plugins` (`-P`) scans the object path for them and lists the
installed plugins, flagging any `requires` command missing from `$PATH`.  The
sample sysmon plugin ships `sysmon.plugin`.  `t/07-check-cli.t`.  Open: using
the manifest at install time (dependency checks, clean uninstall).

**→ M6 is complete** (every item delivered; the "Open" notes above are optional
future refinements, not blockers).  Next: **M7** (de-globalisation) then **M8**
(the non-functional close-out audit).

## M7 — De-globalisation / full modularisation  _(REFACTOR §3 — deferred to end)_
Extract `MenuFile`/`FormFile`/`Action`/`Layout`/`Exec`/`UI::*` into
`lib/CCFE`, add `strict`/`warnings`, replace globals/`local` scope with an
explicit `$ctx`. Done last so it is performed once over settled code, gated by
the conformance tests.

### Progress
- 🔄 **`CCFE::MenuFile`** (done): the `.menu`/`.item` bracket parser is now a
  pure module returning a `{title,top,bottom,path,items}` structure (+ status
  and warnings); `load_menu` keeps the file finding/reading and owns the side
  effects (`%menu`, `$SCREEN_DIR`, the default top message). Refactored to a
  flat dispatch (no cascading-if / deep-nest, so it passes the `src/lib`
  Perl::Critic/perltidy gates the legacy file is exempt from). Unit-tested
  directly in `t/13-menufile.t`; the demo/sysmon fixtures and tty smoke still
  pass.
- 🔄 **`CCFE::FormFile`** (done): the `.form` bracket parser (title/top/bottom/
  path/init/action plus field and separator blocks) is now a pure module of the
  same shape, dispatch-table driven (`%FIELD_ATTR`/`%SEP_ATTR` closures, no
  cascading-if). `load_form` keeps the file finding/reading and the effectful
  rest — command/boolean defaults, **the `$COLS`-dependent separator label
  formatting** (centre / rule-line, which the parser deliberately defers as
  layout not parsing), select-item resolution and the `%form`/`$SCREEN_DIR`
  side effects. This cut ~325 lines of inline parser to a ~20-line call. Unit-
  tested in `t/14-formfile.t` (40 cases); the multipage-form pty test and full
  suite (235 tests) stay green. Next: `Config`, `Action`, the pure `Layout`
  helpers, and finally the `$ctx` threading.

## M8 — Non-functional close-out audit  _(final gate)_
Five dimensions: **test coverage, code quality, performance, security,
documentation**. Produce a short report, fix what's cheap, file the rest.

---

### Progress
- ✅ **M0** — `LICENSE`, `CHANGELOG.md` (git-history policy), config backup/VCS docs.
- ✅ **M1** — layout reorganised and **v2.0 cut**: menus/forms in
  `share/ccfe/objects/`, themes in `share/ccfe/themes/`, per-user files on XDG
  dirs (with `~/.ccfe` fallback); installer, search paths, `print_config`
  (`OBJ_DIR`/`THEME_DIR`), the sysmon plugin installer and the docs updated;
  `MIGRATION.md` added. 106 tests green.
- ✅ **M2** — runtime configuration: `ccfe.pl` resolves its paths from its own
  location (FindBin), so it installs **byte-identical** (no `sed` templating),
  is **relocatable**, runs via `PATH`, and supports `CCFE_*_DIR` env overrides
  for split/FHS layouts. Verified by moving an install and invoking by name.
- ✅ **M3** — packaging: a **Debian package** (`debian/`) built and verified
  here (`dpkg-buildpackage` → `ccfe_2.0_all.deb`; staged via `install.sh`,
  `/usr/bin/ccfe` symlink, runs from the packaged tree). RPM spec and Alpine
  `APKBUILD` provided under `packaging/` (mirror the deb; not built here — no
  `rpmbuild`/`abuild`). Fixed `use lib` to resolve a symlinked invocation.
- ✅ **M4** — multi-page forms: pagination existed but page **navigation was
  invisible** — libform switches the logical page but doesn't repaint a derwin
  sub-window, and ncurses' update optimisation missed the change. Fixed with
  `redraw_form_page()` (unpost/post + `clearok`). A 40-field form now paginates
  and navigates (PgUp/PgDn); regression test `t/08-multipage-form.t`.
- ✅ **M5** — guided builders: `ccfe builder` (a menu + forms) and the
  `ccfe-build` backend let users create/extend menus, forms and config — "CCFE
  building CCFE" — writing to the XDG dir, validating with `ccfe -k`, and taking
  input injection-safely via `$CCFE_FIELD_*`. Tests in `t/09-builder.t`.
- ✅ **M6** — UX & quality polish (released as **2.1**): full terminal-resize
  reflow (vertical + horizontal, re-wrap, no crash) and pop-up/menu repaint
  fixes; display-column (UTF-8) layout; long-label wrapping; the full fg/bg
  colour palette + panelled `smit-panel` theme with themed markers/dots and a
  `show_dots` switch; graceful uncaught-error handling; machine-readable
  `--dump` (JSON); opt-in `mouse`; and the `--plugins` manifest lister. Tests
  `t/06`/`t/07`/`t/10`/`t/11`/`t/12`; see the detailed list above.

### Done before this roadmap (post-v1.60)
Security/restricted mode, the `CCFE::Restrict`/`CCFE::Theme` module
foundation, perlcritic/perltidy/CI gates, optional colour incl. menu/header/
control-key theming and the classic + colour SMIT themes, and the `-k` linter.
