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
its window+post on `KEY_RESIZE` at the new `$LINES`/`$COLS`; regression test
`t/10-resize.t`. Open: full horizontal re-layout of form fields, and
`do_list`/`run_browse` reflow.

## M7 — De-globalisation / full modularisation  _(REFACTOR §3 — deferred to end)_
Extract `MenuFile`/`FormFile`/`Action`/`Layout`/`Exec`/`UI::*` into
`lib/CCFE`, add `strict`/`warnings`, replace globals/`local` scope with an
explicit `$ctx`. Done last so it is performed once over settled code, gated by
the conformance tests.

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

### Done before this roadmap (post-v1.60)
Security/restricted mode, the `CCFE::Restrict`/`CCFE::Theme` module
foundation, perlcritic/perltidy/CI gates, optional colour incl. menu/header/
control-key theming and the classic + colour SMIT themes, and the `-k` linter.
