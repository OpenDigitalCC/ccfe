# M8 — Non-functional close-out audit

Five-dimension review of CCFE at the post-M7 state (v2.1.1, `use v5.36`, 313
tests). Each dimension below gives a verdict, the findings, and whether each was
**fixed in this audit** or **filed** for later. Cheap, safe fixes were applied
now; structural and design-level items are filed (tracked in
`FEATURE-REQUESTS.md`).

Overall: the codebase is in good shape. The pure `CCFE::*` modules are
excellent across every dimension; the residual debt is concentrated in the
legacy `ccfe.pl` body (size/complexity) and in the **security model of
RESTRICTED mode**, which is the one finding that materially changes how CCFE
should be described and deployed.

---

## 1. Test coverage

**Verdict: strong where it's been invested (modules), with real gaps in the
`ccfe.pl` interior.** Measured with `Devel::Cover` (require-based + module
tests; the pty tests exec a separate, uninstrumented process, so true `ccfe.pl`
coverage is higher than the raw number):

| Unit | stmt | branch | sub | total |
|------|------|--------|-----|-------|
| Action / Config / Context | 100 | 100 | 100 | **100** |
| MenuFile | 100 | 100 | 100 | 97.3 |
| Restrict | 100 | 100 | 100 | 97.0 |
| Layout | 100 | 87.5 | 100 | 96.6 |
| FormFile | 98.9 | 93.7 | 100 | 92.7 |
| Theme | 70.6 | 75.0 | 80 | 70.1 |

Findings:
- **[med] Output-browser interior untested** — `run_browse`'s `/`+`n` search
  (`get_search_buff`/`search_next`/`search_all`) and the save-to-file /
  save-to-runnable-script paths never run. The pty harness makes these
  testable. *Filed.*
- **[med] Error/failure branches untested** — `exec_command` command-not-found,
  the silent `list_cmd` failure behind issue #1 (guarded only by source-pattern
  match in `t/02`), file-open errors in save. The pty harness those tests asked
  for now exists. *Filed.*
- **[med] F7 shell-escape runtime path** — denial is unit-tested; the allowed
  spawn-and-return is not. *Filed.*
- **[low] `Theme.pm` at 70 %** — the colour-pair init paths need a live
  terminal; could be covered with a small `Curses` mock or a pty assertion.
  *Filed.*
- **[low] CLI: `-s`/`list_shortcuts`, `--help`/`--version`** untested (vs
  `-k`/`--dump`/`--plugins` which are). Trivial to add to `t/07`. *Filed.*

## 2. Code quality

**Verdict: modules pristine; the debt is all in `ccfe.pl`, correctly kept out
of the CI perlcritic gate.** `perlcritic src/lib` is clean at severity 3.
`ccfe.pl` shows 107 sev-5 / 441 sev-3 — but the bulk is intentional legacy idiom
(bareword filehandles, stringy `eval` for colour config, non-lexical loop
iterators) that would be churn-for-churn to "fix".

**Fixed now:**
- 3 string-vs-numeric operator mismatches on counts (`$c eq 0`, `$nfound eq 2`,
  `$nfound ge 2` → `==`/`>=`).
- 2 confirmed-unused lexicals removed (`$labelLen`, `$sc` — the latter left over
  from the FormFile extraction).
- `ralign()` rewritten from an `eval`-string to a plain `sprintf` (also a
  security fix — see §4).
- Version strings reconciled to 2.1.1 (README, RPM spec, Alpine APKBUILD,
  packaging README) and the RPM/Alpine perl floor set to `>= 5.36`.

**Filed:**
- **Six oversized subs** dominate the complexity — `do_form` (1392 lines,
  cyclomatic 285), `load_config` (582), `run_browse` (543), `do_list` (350),
  `do_menu` (331), `load_form` (224). `do_form` is the clear refactor target.
- The colour/attribute config dispatch is a long copy-pasted `if/elsif` of
  `eval "$ctx->{cfg}{X} = …"` arms — table-driveable (and see §4 for the eval).
- `ccfe.pl` is ~817 lines off perltidy; reformatting is high-churn and best done
  alongside breaking up the big subs, so it stays ungated for now.

## 3. Performance

**Verdict: sound for an interactive TUI — no must-fix.** Scrolling uses a
pre-built `curses` pad with O(1) `prefresh`; menu/form navigation delegates to
the ncurses `menu_driver`/`form_driver`; heavy window/field rebuild is correctly
gated to `KEY_RESIZE`, not run per keystroke. Startup parsing is linear and
one-shot.

Findings (all low, all filed):
- The streaming output-capture loop calls `trace(…, $LOG_ACTION_OUT)` per line,
  and both `trace()` and the new `$SIG{__WARN__}` handler open/append/close the
  log **per event**. In normal use this is dormant (`$LOG_ACTION_OUT` is off at
  the default log level; warnings are rare on hot paths), but a user who raises
  the log level gets per-line file I/O while a command streams. Cheap future
  fix: open the log once around the capture loop / hold a handle.
- `trace()` builds `@months` + `localtime` before checking whether logging is
  even on — trivial, move the gate first.
- `/`-search reads each pad cell with a char-at-a-time `inchnstr`; one-shot per
  search, bounded by `MAX_PAD_LINES`. Could read a row per call. Low.

## 4. Security

**Verdict: RESTRICTED mode is a *guardrail*, not a security boundary.** It
reliably blocks the casual interactive escapes it was built for (F7 shell,
save-as-runnable-script, `system:`/`exec:` of non-allowlisted program names),
and the supporting hygiene is sound — `harden_child_env` strips `LD_*`/`BASH_ENV`
/`ENV`/`CDPATH` and resets `IFS`; temp files use `O_EXCL`; persistent files are
`0600` under the user's own dir; the log is `umask 0177`. But it is **not** a
boundary against a motivated local user.

**Fixed now:**
- `ralign()` `eval`-string → `sprintf` (removed a latent Perl-injection smell on
  boolean-field defaults).
- Documented the real scope of RESTRICTED in the README (it previously read as a
  stronger guarantee than the code provides).

**Filed (the RESTRICTED hardening — needs design, see FEATURE-REQUESTS):**
- **[high] User config can switch RESTRICTED off.** `load_config` applies every
  file on `@cnf_path` in order (system → `~/.config/ccfe` → legacy) with
  last-wins and no "system locks the value", and the search paths honour
  user-controlled `CCFE_*_DIR`/`XDG_*`. A user re-sets `restricted = no`. Fix
  direction: a locked/system-config mode that user config cannot weaken.
- **[high] Menus/forms load from user-writable dirs.** `@mf_path` includes
  `~/.local/share/ccfe` and honours `CCFE_OBJ_DIR`/`-l`. A user authors any
  `run:` action (never allowlisted) → arbitrary command execution. Fix
  direction: refuse user-writable object/config dirs in restricted deployments.
- **[high] Allowlist is bypassable by shell chaining.** Actions run via
  `/bin/sh -c`, but the allowlist only checks the first token's basename, so
  `system: df; sh`, `df $(sh)`, backticks all pass. Same for `%{FIELD}` values
  substituted into args before the check. Fix direction: argv-based (shell-free)
  exec so the allowlist actually constrains what runs.
- **[med] `eval "$VAR = $attrv"` in `load_config`** executes arbitrary Perl from
  a config value (colour/attr settings). Trusted-config assumption, but combined
  with the above it's an in-process code-exec primitive. Fix direction: validate
  `$attrv` against the expected `A_*`/`COLOR_PAIR(n)`/`color_pair('x','y')`
  grammar (or parse, don't eval).
- **[low] CWD (`.`) on `$PATH`** in `run_browse`; **[low]** `$prompt` in
  `call_shell` interpolated into a shell string. Both filed (the `.`-on-PATH
  change risks breaking menus that call a script in their own dir, so it needs a
  deliberate decision, not a drive-by edit).

## 5. Documentation

**Verdict: README prose is good and current on M6 features; the gaps are the
man pages and a couple of self-contradictions, mostly cheap.**

**Fixed now:**
- README version line 2.0 → 2.1.1; the `man ccfe-menu`/`ccfe-form` (hyphen)
  references corrected to the actual `ccfe_menu`/`ccfe_form` page names; the
  stale "a future release reorganises these paths" caveat updated (that reorg
  shipped in 2.0).
- ROADMAP self-contradiction (the `$ctx` bullet still tagged 🔄 "in progress"
  while the rest says M7 complete) → ✅; `M7-CTX-PLAN.md` given a COMPLETE
  banner.

**Filed:**
- **[high] Man pages are stale** — `ccfe.1` etc. still say version 1.58, document
  the pre-v2 `/usr/lib/ccfe` layout, and omit every M6 flag (`-k`, `-D/--dump`,
  `-P/--plugins`) and feature (mouse, colour, resize). Needs a rewrite pass.
- **[med] Deb ships man pages off the MANPATH** (`/usr/lib/ccfe/man/...`), so
  `man ccfe` won't resolve from a package install despite the README saying it
  will. Packaging fix (symlink/install into the man hierarchy).
- **[med] No POD / contributor architecture doc** — the `CCFE::*` modules have
  good header comments but zero POD, and there's no "lib/CCFE overview" for a
  new contributor. Additive.
- **[low] Two licence files** (`LICENCE` 2021 + `LICENSE` 2026) and a stale
  `doc/ChangeLog` in the staged tree — tidy up.

---

## What was fixed in this audit

`ccfe.pl`: 3 numeric operators, 2 dead lexicals, `ralign` eval→sprintf.
Docs: README (version, man-page names, RESTRICTED scope, backup caveat),
ROADMAP + M7-CTX-PLAN consistency. Packaging: version 2.1.1 across
RPM/Alpine/packaging-README, perl `>= 5.36` floor on RPM/Alpine. All 313 tests
stay green.

## What is filed (recommended next, roughly by priority)

1. **RESTRICTED-mode hardening** (the §4 high items) — locked system config,
   read-only object dirs in restricted deployments, shell-free argv exec, and
   `eval`-free colour-config parsing. This is the highest-value follow-up.
2. **Coverage**: pty tests for the browser search/save paths, `exec_command`
   failure (the real issue-#1 repro), and F7 shell-escape.
3. **`do_form` (and the other oversized subs) refactor**, with a perltidy pass
   and man-page rewrite once the structure settles.
4. **Packaging**: man pages onto the MANPATH; module POD + a contributor doc.

Performance items are genuinely low priority. None of the filed items block a
2.2 release.
