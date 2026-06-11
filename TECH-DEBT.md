# CCFE — technical debt backlog

Actionable work packages distilled from the M8 close-out audit (`M8-AUDIT.md`).
Each is self-contained and issue-ready: scope, steps, acceptance criteria,
effort and dependencies. Ordered by recommended priority.

Effort key: **S** ≈ <½ day, **M** ≈ 1–2 days, **L** ≈ several days.
All work must keep the suite green and the four CI checks passing
(`perl -c`, `prove -lr t/`, `perlcritic src/lib`, perltidy on `src/lib`).

| ID | Title | Dimension | Priority | Effort | Depends on |
|----|-------|-----------|----------|--------|-----------|
| TD-1 | RESTRICTED-mode hardening | security | **high** | L (4 sub-tasks) | — |
| TD-2 | Close the pty test-coverage gaps | coverage | high | M | — |
| TD-3 | Break up the oversized `ccfe.pl` subs | quality | med | L | TD-2 |
| TD-4 | Docs & packaging polish (man pages, POD) | docs | med | M | — |
| TD-5 | Logging I/O polish | performance | low | S | — |

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

---

> Filing: these map cleanly onto GitHub issues (one per TD-N, with TD-1's
> sub-tasks as a checklist or four linked issues). Say the word and they can be
> opened against the remote.
