# CCFE — technical debt backlog

Actionable work packages distilled from the M8 close-out audit (`M8-AUDIT.md`).
Each is self-contained and issue-ready: scope, steps, acceptance criteria,
effort and dependencies. Ordered by recommended priority.

Effort key: **S** ≈ <½ day, **M** ≈ 1–2 days, **L** ≈ several days.
All work must keep the suite green and the four CI checks passing
(`perl -c`, `prove -lr t/`, `perlcritic src/lib`, perltidy on `src/lib`).

| ID | Title | Dimension | Priority | Effort | Depends on | Status |
|----|-------|-----------|----------|--------|-----------|--------|
| TD-1 | RESTRICTED-mode hardening | security | **high** | L (4 sub-tasks) | — | ✅ done |
| TD-2 | Close the pty test-coverage gaps | coverage | high | M | — | ✅ done |
| TD-3 | Break up the oversized `ccfe.pl` subs | quality | med | L | TD-2 | 🟡 in progress |
| TD-4 | Docs & packaging polish (man pages, POD) | docs | med | M | — | ✅ done |
| TD-5 | Logging I/O polish | performance | low | S | — | ✅ done |

**TD-1 done** (`restricted = yes` strengthened to a real boundary, per the
agreed approach): TD-1d eval-free colour parsing (`attr_value`), TD-1c shell-free
argv exec for system:/exec:, TD-1a config-lock against user-writable files,
TD-1b user-writable object-dir refusal. Proven by t/25–t/27; README "Restricted
mode" updated. **TD-2 done**: pty coverage for the browser (search/save), the
issue-#1 empty-list repro, F7 shell-escape, the `-s`/`-v`/`-h` CLI; fixed three
latent warnings (two in `list_shortcuts`) along the way. Test count 313 → 351.

**TD-3 in progress** — `do_form` broken up from **1392 → 590 lines**. First the
field-creation loop, the init-command phase and the `KEY_RESIZE` rebuild were
lifted (`build_form_fields`, `run_form_init`, `resize_form`), and the
confirm/log/wait_key opts handling was shared with `do_menu`
(`apply_action_opts`). Then the four big event-loop arms became helpers:
`run_form_submit` (Enter dispatch: run/form/system/exec), `form_value_list`
(F2 chooser; returns a break flag for the ES_EXIT case), `form_tab_cycle`
(TAB/Shift-TAB single-val cycling) and `form_save_fields` (Save). The event
loop is now a thin dispatcher of mostly one-line arms. Each extraction was
guarded by the form behaviour net, which was first strengthened with three new
pty tests (t/29 fields/nav/separator/boolean, t/30 F2-list/F5-preview,
t/31 TAB-cycle/Save) — test count 351 → 366. The remaining `do_form` bulk is the
per-call helper closures (kept as closures to preserve the M7 "won't stay
shared" fix) and setup/teardown.

`load_config` broken up **592 → 496 lines**: the ~20-arm colour/attribute
cascade across `field_attr{}`/`active_field_attr{}`/`menu_global{}`/
`browser_global{}` is now four name→cfg-key maps + an `apply_attr_section()`
helper (overlaps the done TD-1d `attr_value`). Verified semantically verbatim
(t/06, t/15, plus a direct cfg-value check that each section applies its
configured `COLOR_PAIR` to the right key while a bogus key still errors).

`run_browse` broken up **543 → 363 lines**: its four nested *named* subs
(`get_search_buff`/`search_next`/`search_all`/`load_pad`) were hoisted to file
scope — they only ever touched the package-global pad state run_browse
`local`-ises, so the move is behaviour-identical (a named sub already compiles
at package scope) and de-nests the misleading "sub inside sub" shape. Then the
Save arm became `browser_save()` (returns a break flag for the two ES_EXIT
cases). Verified by t/21 (search drives all three search helpers) and t/22
(save: picker/script/file write).

The three mid-sized subs were also broken up: `do_menu` **308 → 230** via
`run_menu_action()` (the menu analogue of `run_form_submit`: parse the item
action, apply its opts, dispatch menu/form/system/exec/run); `do_list`
**344 → 295** via `list_setup()` (per-type footer keys / top message + the
`display` line-wrap, also fixing a latent uninit-value warning); `load_form`
**224 → 120** via `resolve_field_defaults()` (the per-field const/command/
boolean default resolution + attribute filling). Verified by t/28/t/12,
t/23/t/30, and t/14/t/19/t/20/t/29 respectively; full suite green (366).

Still open under TD-3: `run_browse`'s open3 + `IO::Select` capture phase (~135
lines — the most I/O-sensitive part: child spawn, stdout/stderr multiplexing,
partial-line handling — left for now as higher-risk with less certain edge-case
coverage); and the `ccfe.pl` perltidy pass + CI-gate decision (a policy call on
perltidy/perlcritic severity for the legacy file).

---

## TD-1 — RESTRICTED-mode hardening  *(security, high, L)*

**Why.** The audit's headline finding: RESTRICTED mode is a guardrail, not a
security boundary. A motivated local user can defeat it. It is now *documented*
as such (README §"Restricted mode"), but to make it a real kiosk boundary it
needs the four changes below. They are independent and independently shippable;
do the cheapest-value-first or all together behind a new "locked" deployment
mode. **Each needs a design decision on backward compatibility** (existing
restricted setups must keep working, or opt in).

### TD-1a — System config that user config cannot weaken
`load_config` applies every file on `@cnf_path` in order (system `$ETCDIR` →
`~/.config/ccfe` → legacy) with last-wins. A user re-sets `restricted = no`.
- **Do:** once `restricted = yes` (or a new `restricted_lock = yes`) is set by a
  system-owned config, later/user config files must not be able to weaken it —
  ignore attempts to set `restricted = no`, narrow (not widen) `restricted_allow`,
  or change `shell`/`user_shell`/`path` from a less-trusted file. Track which
  file each setting came from (or apply a one-way ratchet).
- **Files:** `src/ccfe.pl` `load_config`; `src/lib/CCFE/Config.pm` already returns
  sections in file order, so the caller can attribute provenance.
- **Accept:** a test where a user config setting `restricted = no` after a system
  `restricted = yes` does NOT re-enable escapes.

### TD-1b — Refuse user-writable config/object dirs in restricted deployments
`@mf_path`/`@cnf_path` include `~/.local/share/ccfe` / `~/.config/ccfe` and honour
`CCFE_*_DIR` / `-l`. A user authors any `run:` action (never allowlisted) → arbitrary
execution.
- **Do:** in a locked/restricted deployment, skip object/config dirs that are
  writable by the invoking user (or not root/system-owned), and ignore the
  `CCFE_*_DIR`/`-l` overrides (or require them to resolve to non-user-writable
  paths). Make the policy explicit and logged.
- **Files:** `src/ccfe.pl` path setup (`@mf_path`/`@cnf_path` build), `load_menu`/
  `load_form` dir scan.
- **Accept:** with the lock on, a `run:` menu placed in `~/.local/share/ccfe/...`
  is not loaded/run.

### TD-1c — Shell-free (argv) execution so the allowlist constrains
Actions run via `/bin/sh -c`, but `CCFE::Restrict::denies_verb` only checks the
first token's basename, so `system: df; sh`, `df $(sh)`, backticks, and `%{FIELD}`
values with metacharacters all bypass it.
- **Do:** for `system:`/`exec:` under RESTRICTED, parse the action into an argv
  list and exec without a shell (or reject any argument containing shell
  metacharacters). Keep `run:` as the explicit "this is a shell command" verb,
  documented as unconstrained. Note `prepare_action` substitutes `%{ID}` *before*
  the verb check — re-order or move to argv so substituted values can't inject.
- **Files:** `src/ccfe.pl` `call_system`/`exec_command`/`prepare_action` and the
  menu/form dispatch; `src/lib/CCFE/Restrict.pm`.
- **Accept:** tests for `system: df; sh` (denied), a field value `; sh` (denied),
  while `system: df -h` still runs.

### TD-1d — eval-free colour/attribute config parsing
`load_config` does `eval "$ctx->{cfg}{X} = $attrv"` for ~20 colour/attr settings;
a config value can run arbitrary Perl in-process.
- **Do:** validate `$attrv` against the expected grammar
  (`A_*`, `COLOR_PAIR(n)`, `color_pair('fg','bg')`, integer, `|`-combinations)
  and build the value with a small parser instead of `eval`. Table-drive the
  ~20 near-identical arms while here (also helps TD-3).
- **Files:** `src/ccfe.pl` `load_config` colour/attr branches (`field_attr`,
  `active_field_attr`, `menu_global`, `browser_global`).
- **Accept:** a config value `0; system("...")` does NOT execute; all existing
  theme files (`ccfe.conf.smit*`) still parse identically (assert via `t/06`).

---

## TD-2 — Close the pty test-coverage gaps  *(coverage, high, M)*

**Why.** The pure modules are 92–100% covered, but `ccfe.pl`'s interactive
interior has real gaps, several on security- or crash-relevant paths. The pty
harness (`src/t/lib/CCFE/Test/Pty.pm`) makes all of these testable now.

**Do — add pty/CLI tests for:**
1. **Output-browser search** — run a command with known output, send `/word`,
   then `n`; assert the match highlights and the pad scrolls. Covers
   `get_search_buff`/`search_next`/`search_all`/`ask_string`.
2. **Save-to-file / save-to-script** — in the browser, save simple + detailed +
   runnable-script; assert files exist with the right mode (the script path is
   `chmod 0755`), the RESTRICTED denial omits the script option, and the
   open-failure branch shows a `disp_msg`.
3. **`exec_command` command-not-found** — the real issue-#1 repro: a form field
   whose `list_cmd` fails silently (F2). Replaces the source-pattern guard in
   `t/02-issue1-regression.t` with an end-to-end run.
4. **F7 shell-escape** — send F7, run a trivial command, `exit` back; assert
   return to the TUI (the allowed path; denial is already unit-tested).
5. **`Theme.pm` init paths** (70% → higher) — a pty assertion that a colour
   config actually allocates pairs, or a small `Curses` stub.
6. **CLI** — extend `t/07` with `ccfe -s`, `--help`, `--version` (exit code +
   a string).

**Accept:** each named sub gains runtime coverage; the issue-#1 test no longer
relies on source-grep. **Do this before TD-3** so the refactor is test-guarded.

---

## TD-3 — Break up the oversized `ccfe.pl` subs  *(quality, med, L)*

**Why.** Six subs carry the structural debt and drive the perltidy/perlcritic
divergence: `do_form` (1392 lines, cyclomatic 285), `load_config` (582),
`run_browse` (543), `do_list` (350), `do_menu` (331), `load_form` (224).

**Do (incrementally, test-guarded by TD-2):**
- Start with `do_form`: extract the field-creation loop, the event loop, and the
  action-dispatch into helpers (several already have pure cores in
  `CCFE::Layout`/`CCFE::Action` to lean on). Then `run_browse` and `load_config`
  (the latter's colour cascade is table-driveable — overlaps TD-1d).
- After the big subs are tractable, run a perltidy pass over `ccfe.pl` and **add
  it to the CI perltidy/perlcritic gate** (currently exempt). Decide a perlcritic
  severity for `ccfe.pl` that holds the line without fighting legacy idiom
  (bareword filehandles, the documented eval-string sites — keep those policies
  exempted as in `.perlcriticrc`).

**Accept:** no sub over an agreed complexity threshold; `ccfe.pl` perltidy-clean
and in the CI gate; suite green throughout.

---

## TD-4 — Docs & packaging polish  *(docs, med, M)*

**Why.** README prose is current, but the reference docs lag and the package
ships man pages users can't find.

**Do:**
- **Man-page rewrite** — `src/man/*` still say version 1.58 and document the
  pre-v2 `/usr/lib/ccfe` layout; they omit every M6 flag (`-k`, `-D/--dump`,
  `-P/--plugins`) and feature (mouse, colour, resize). Rewrite to the 2.2 state.
- **Man pages onto the MANPATH** — the deb stages them under
  `/usr/lib/ccfe/man/...`, off the man search path, so `man ccfe` fails from a
  package install despite the README. Symlink/install into the man hierarchy
  (`debian/ccfe.links` or `dh_installman`).
- **Module POD + contributor doc** — the `CCFE::*` modules have good header
  comments but zero POD (`perldoc CCFE::FormFile` is empty). Add a one-paragraph
  `=head1`/`=head1 FUNCTIONS` per module and a short `lib/CCFE` architecture
  overview for contributors.
- **Tidy** — two licence files (`LICENCE` 2021 + `LICENSE` 2026) and a stale
  `doc/ChangeLog` in the staged tree; consolidate.

**Accept:** `man ccfe` works from a package install and documents current flags;
`perldoc CCFE::X` yields content; one contributor architecture doc exists.

**Done.** `.TH` version 1.58 → 2.2 on all five pages; `ccfe.1` documents the M6
options `-D/--dump`, `-k`, `-P/--plugins`; `ccfe.conf.5` documents the
previously-undocumented `mouse`, `restricted`, `restricted_allow` and the
`menu_global` colour attributes (`screen_attr`/`item_attr`/`selected_attr`/
`title_attr`/`key_attr`), each verified against `load_config`. Man pages are put
on the MANPATH via `/usr/share/man` symlinks in `debian/ccfe.links` (the
self-contained tree under `/usr/lib/ccfe` is otherwise off the search path). All
eight `CCFE::*` modules gained `=head1 NAME/SYNOPSIS/DESCRIPTION/FUNCTIONS/SEE
ALSO` POD (podchecker-clean, Pod::Text renders), plus a contributor architecture
overview at `src/lib/CCFE/README.md`. Licence files consolidated to `LICENCE`
(British, the original); the stale upstream `ChangeLog` is no longer shipped by
`install.sh`. The pre-v2 `/usr/lib/ccfe` example paths in `ccfe_menu.5` were left
as-is — they are coincidentally correct for the deb's default `LIBDIR`. Note: no
config keyword controls resize (it is handled at runtime via `KEY_RESIZE`), so
there was nothing to document there.

---

## TD-5 — Logging I/O polish  *(performance, low, S)*

**Why.** Genuinely low priority (a TUI), but two spots do per-event file I/O.

**Do:**
- Hold the log handle open (or open once around the output-capture loop) instead
  of open/append/close per line in the streaming `trace(…, $LOG_ACTION_OUT)` and
  per warning in the `$SIG{__WARN__}` handler. Only bites when the log level is
  raised, but cheap to make robust.
- In `trace()`, move the `LOG_FNAME` gate ahead of the unconditional
  `localtime`/`@months` work.

**Accept:** no behaviour change; a high-log-level streaming command no longer
open/closes the log per line.

**Done.** A shared `_log_write()` holds the log handle open and reuses it across
calls (3-arg append open so a crafted `LOG_FNAME` cannot smuggle a pipe/redirect;
autoflush keeps each line on disk immediately, so the old open/append/close
per-line visibility is preserved). Both `trace()` and `$SIG{__WARN__}` write
through it. `trace()` now returns early on `!LOG_FNAME` / level-not-set before any
`localtime`/`@months`/`caller` work. Verified by t/10 and t/11 (which read the
log post-exit, including raised-level `resize_form` traces); full suite green.

---

> Filing: these map cleanly onto GitHub issues (one per TD-N, with TD-1's
> sub-tasks as a checklist or four linked issues). Say the word and they can be
> opened against the remote.
