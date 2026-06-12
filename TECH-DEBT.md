# CCFE — technical debt backlog (CLOSED)

The work packages distilled from the M8 close-out audit (`M8-AUDIT.md`) are all
resolved. This file is now a closeout record; the per-package scope/steps that
used to live here are spent — see the git history and the cited tests for the
detail. Throughout, the suite stayed green and the CI checks kept passing
(`perl -c`, `prove -lr t/`, `perlcritic`, `perltidy`).

| ID | Title | Dimension | Status |
|----|-------|-----------|--------|
| TD-1 | RESTRICTED-mode hardening | security | ✅ done |
| TD-2 | Close the pty test-coverage gaps | coverage | ✅ done |
| TD-3 | Break up the oversized `ccfe.pl` subs | quality | ✅ done |
| TD-4 | Docs & packaging polish (man pages, POD) | docs | ✅ done |
| TD-5 | Logging I/O polish | performance | ✅ done |

**TD-1 — RESTRICTED is now a real boundary, not a guardrail.** Config-lock so
user-writable config can't weaken it (TD-1a), refusal of user-writable
object/config dirs (TD-1b), shell-free argv exec for `system:`/`exec:` so the
allow-list actually constrains (TD-1c), and eval-free colour/attr config parsing
(`attr_value`, TD-1d). Proven by `t/25`–`t/27`; README "Restricted mode" updated.

**TD-2 — interactive coverage.** pty tests for the output-browser search/save
paths, the issue-#1 empty-list repro, F7 shell-escape, and the `-s`/`-v`/`-h`
CLI; three latent warnings fixed along the way (two in `list_shortcuts`).

**TD-3 — every audited sub broken up**, each extraction test-guarded:
`do_form` 1392→590, `load_config` 592→496, `run_browse` 543→272, `do_list`
344→295, `do_menu` 331→230, `load_form` 224→120. The do_form/browser event-loop
test net was built first (`t/29`–`t/32`). Finally `ccfe.pl` was made
perltidy-clean and brought **into the CI gate** — perltidy alongside `src/lib`,
and a dedicated `.perlcriticrc-ccfe` (severity 5, legacy idioms exempted) so the
strict `src/lib` profile is untouched.

**TD-4 — docs & packaging.** Man pages updated to 2.2 with the M6 options
(`-D/--dump`, `-k`, `-P/--plugins`) and put on the MANPATH via
`debian/ccfe.links`; `ccfe.conf(5)` gained the undocumented params (mouse,
restricted[_allow], menu colour attrs) and the `variables {}` section; POD added
to all eight `CCFE::*` modules plus a `lib/CCFE/README.md` architecture overview;
the duplicate licence file and the stale shipped `ChangeLog` were consolidated.

**TD-5 — logging I/O.** A shared, persistent, autoflushed log handle
(`_log_write`, used by `trace()` and the `$SIG{__WARN__}` handler) replaces the
open/append/close-per-line pattern, and `trace()` now gates on the log level
before doing any timestamp work.

> Future work is feature work — see `FEATURE-REQUESTS.md`. New high-severity
> findings should be filed there or as fresh issues, not appended here.
