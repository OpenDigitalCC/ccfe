# M7 — `$ctx` threading plan (de-globalisation finish)

The pure-parser/geometry extractions (REFACTOR.md §3.1–3.2, first half) are
done: `CCFE::MenuFile`, `FormFile`, `Config`, `Action`, `Layout` are split out,
unit-tested, and released in 2.1.1. What remains of M7 is the harder half:
**replace the package globals and `local` dynamic scope in `ccfe.pl` with an
explicit `$ctx` state object** (REFACTOR.md §3.2, bullet 3 — "the spookiest
action-at-a-distance in the code").

This file is the execution plan: what to thread, in what order, and where to
stop. Every step keeps all **302 tests green** and the `ccfe-plugin-sysmon`
conformance fixture installing and running unchanged.

---

## 1. Inventory — not all globals are equal

`ccfe.pl` (~5,200 lines, 46 subs, no `use strict`) declares its globals as
barewords at file scope (`:76–276`). They fall into four groups with very
different threading value:

| Group | Examples | Count | Mutated after startup? | Thread it? |
|-------|----------|-------|------------------------|------------|
| **A. Constants** | `$NO/$YES`, `$ES_*`, type consts (`$STRING`…), row dims (`$MS_*`,`$FS_*`,`$RS_*`), `%bool_vals`/`%type_vals`/`%sep_type_vals`, margins | ~120 | No | **No** — leave as read-only package vars; `our`-declare them at the Phase 6 capstone (a `CCFE::Const` extraction is optional polish, not required for threading or strict) |
| **B. Config settings** | `$LAYOUT`, `$HIDE_CURSOR`, `$ENABLE_MOUSE`, `$SHOW_DOTS`, `$FIELD_VALUE_POS`, the 17 colour-attr vars (`$labelFg`…`$MENU_*_ATTR`), `%keys`, `$RESTRICTED`/`@RESTRICTED_ALLOW` | ~30 | Once, by `load_config` | **Yes** — one read-only `$ctx->{cfg}` sub-object |
| **C. Runtime mutable state** | `%form` (~160 sites), `%menu` (~38), `%field_vals` (8), `@fp`, `$cform`, `$SCREEN_DIR`, `$last_item_id`, `$pad_lines`, `$exec_args` | ~250 sites | Continuously, per screen | **Yes** — this is the real target |
| **D. Curses / process** | `$LINES`, `$COLS` (Curses-owned, 81 reads), `$cpid`/`$tmpfh` (SIGINT handler) | — | By the library / signals | **No** — not ours; leave |

**Key decision:** scope `$ctx` to groups **B + C**. Threading the ~120 group-A
constants through every signature is pure noise for zero correctness gain; they
become an imported constant namespace instead. This roughly halves the churn
and the risk versus a literal "thread all `:76–276`" reading of REFACTOR.md.

## 2. The hard part — the nested-sub trap

`do_form`, `do_menu` and `run_browse` use `local %form / @fp / $cform /
%field_vals / %menu` and define **named** inner subs that read them:

- in `do_form`: `sync_fields_val`, `set_field_attr`, `set_field_active_attr`,
  `check_val_changes`, `prepare_action`, `save_persistent`, `load_persistent`
- in `run_browse`: `get_search_buff`, `search_next`, `search_all`, `load_pad`
- in `init_footer`: `sort_fnkeys`

A Perl **named** sub does *not* close over a per-call lexical — it binds the
first call's copy. These inner subs work today *only* because `local` makes the
globals dynamically scoped, so each `do_form` call's `local %form` is the one
the inner subs see for the duration of that call. Removing `local %form` breaks
that unless each inner sub is converted to **either**:

- **(a) an anonymous closure** `my $sync = sub { ... $ctx ... };` created inside
  the call (genuinely closes over that call's `my $ctx`), **or**
- **(b) a top-level sub taking `$ctx` explicitly** `sync_fields_val($ctx, …)`.

Recommendation: **(b)** for subs that are conceptually standalone
(`save_persistent`, `prepare_action`, `load_persistent` — they belong at file
scope and are independently testable once they take `$ctx`); **(a)** only for
the few that are truly part of the loop's inner machinery. Solving this on the
*smallest* structure first (Phase 1) de-risks it before `%form`.

## 3. Phased, individually-shippable steps

Each phase is one (or a few) commits, each keeping the full suite + sysmon
fixture green. The pty tests (`t/03` smoke, `t/08` multipage, `t/10` resize) are
the integration guard — they drive `do_menu`/`do_form` with real state, so a
threading mistake shows up as a crash or a mis-drawn screen, not a silent pass.

### Phase 0 — container scaffolding + deb floor  *(done — low risk)*
- `CCFE::Context::new()` returns a fresh run-state hashref (`{ cfg => {} }`);
  `$ctx` is built once in `ccfe.pl`'s main body, just before `load_config`.
  Nothing reads it yet — pure scaffolding, no behaviour change. Unit-tested in
  `t/18-context.t`.
- Folded in the latent packaging fix: `debian/control` now declares
  `perl (>= 5.36.0)` in `Depends` and `Build-Depends` (the `lib/CCFE/*` modules
  already require 5.36, so the floor was under-specified). The next release
  changelog records it.
- **Deferred from this phase:** the group-A constants → `CCFE::Const` move.
  It is not load-bearing for threading, and for the capstone the constants only
  need `our`-declaring in place; moving ~120 of them up front is churn/risk for
  no near-term gain. Handle at Phase 6 (or skip — it is optional polish).

### Phase 1 — `%field_vals` → per-call lexical  *(done — the pattern-setter)*
- Reality check vs. the plan: only **one** nested sub actually reads
  `%field_vals` — `load_persistent` (not `sync_fields_val`/`save_persistent`,
  which the inventory had wrongly assumed). 6 sites total, all inside `do_form`.
- **Design refinement (applies to Phases 2–3 too):** `%field_vals` is `local`,
  i.e. *per-call* recursion state, so it became a per-call **lexical**
  `my $field_vals = {}` — **not** a key on the single startup `$ctx`. A shared
  `$ctx->{field_vals} = {}` per call would clobber a parent screen on nesting;
  the lexical preserves the old `local` save/restore exactly. The startup `$ctx`
  stays for the genuinely shared state (cfg/process). So per-screen state
  (field_vals, menu, form, fp, cform) lives in per-call containers; `$ctx` holds
  the shared parts. Nested `load_persistent` takes the map as an explicit
  parameter (option b), sidestepping the named-sub closure trap.
- **Coverage gap closed:** the gate the plan named ("field-values + persistent
  tests") did not exist — the pty tests only navigate default/empty fields.
  Added `t/19-form-init.t`, which drives a form whose `init { command:… }`
  pre-fills a field and asserts the value renders, exercising the field_vals
  write (init parse) and read (field creation) sites this phase changed.
- **Gate:** full suite (309 tests) + the new `t/19` green.

### Phase 2 — `%menu` → per-call lexical  *(done)*
- Low-churn shape: `load_menu` now fills a **caller-provided hashref**
  (`load_menu($name, \%menu)`); each caller declares a lexical `my %menu` so the
  ~30 `$menu{X}` read sites stay byte-identical, just bound to the lexical
  instead of the global. `do_menu`'s `local %menu` → `my %menu`; its anonymous
  draw/resize closures capture the lexical correctly (no named-sub trap, unlike
  `do_form`).
- **Caller count was 3, not 1:** besides `do_menu`, the `--dump`/`-k` path
  (`dump_shortcut`, `check_shortcut`) also calls `load_menu` and read the global
  — both updated to pass `\%menu`.
- **Test fallout:** `t/01-parsers.t` drove `load_menu('ccfe')` and read the
  global `%menu`; updated to the new signature. (The form half still reads
  global `%form` — that is Phase 3.)
- **Noted, not touched:** `load_menu`'s `$$path = $dir` writes through an
  undef global `$path` (a vestigial no-op under no-strict; the real path
  side-effect is `$SCREEN_DIR`). Left as-is; revisit at the strict capstone.
- **Gate:** `t/03` smoke, `t/07` (`-k` item count + `--dump` JSON items array),
  `t/01` parser unit. Full suite 309 green.

### Phase 3 — `%form` + `@fp` + `$cform` → per-call lexicals  *(done — the big one)*
- ~162 `%form` + 50 `@fp` + 113 `$cform` sites; the bulk of the value, killing
  the `local %form` dynamic scope. Done in two commits:
- **3a** — convert `do_form`'s seven nested **named** subs (sync_fields_val,
  set_field_attr, set_field_active_attr, check_val_changes, prepare_action,
  save_persistent, load_persistent) to forward-declared **anonymous closures**.
  Bodies unchanged; at this step they still read the `local` globals, so
  behaviour is identical. This is the prerequisite — a named sub binds the first
  call's lexical, so it cannot capture a per-call `my %form`.
- **3b** — flip `do_form`'s `local @fp/$cform/%form` to `my`. The ~325 body
  sites stay byte-identical (lexical hash/array/scalar use the same sigils); the
  closures and `resize_form` (already anonymous) now capture the lexicals.
  `load_form` builds into a lexical `%form` and **copies it out** to a new
  caller-ref parameter at the end (so its ~40 internal sites stay unchanged
  rather than converting to `$form->{}`). `do_form` passes `\%form`; that ref is
  the same hash the closures captured, so `load_form` filling it in place is
  seen by them. The `--dump`/`-k` `dump_shortcut`/`check_shortcut` form branch
  also updated. `t/01-parsers.t` form section updated to the new signature.
- **Coverage added:** `t/20-form-submit.t` drives Enter to run a form's action
  with `%{FIELD}` substitution, firing the submit-path closures (sync_fields_val,
  prepare_action) that the open/navigate tests never reached. (A manual F6 check
  separately confirmed save_persistent.) Note found along the way: **Enter**
  submits/runs the action; **F6** is save-persistent — not the reverse.
- **Gate:** `t/03` menu→form, `t/08` multipage, `t/10` resize (fires the
  resize_form closure), `t/11` layout, `t/07` `--dump` form, `t/20` submit. Full
  suite 311 green.

### Phase 4 — config settings → `$ctx->{cfg}`  *(done — ~45 vars, ~290 sites)*
- **Decision (agreed):** config is read-only-after-startup shared state, so it
  is *consolidated* into one explicit `$ctx->{cfg}` object rather than
  param-threaded through the ~15 reading subs. `$ctx` is promoted to a top-level
  `our` global, built before the config defaults; `load_config`, the defaults
  and every reader fill/read `$ctx->{cfg}{X}`. No param-threading (no benefit for
  immutable data); the per-call MUTABLE state already got true lexical isolation
  in Phases 1–3.
- Done in three test-gated word-boundary-rename commits: **4a** scalar settings
  (LAYOUT, HIDE_CURSOR, PATH, RESTRICTED, *_FOOTER_ROWS, …); **4b** colour/attr
  vars incl. the `eval "$VAR = ..."` ones (rewritten to
  `eval "\$ctx->{cfg}{labelFg} = ..."`, still evaluated in `ccfe.pl`'s package);
  **4c** structures (`%keys` → `$ctx->{cfg}{keys}` hashref, `@fval_delim` and
  `@RESTRICTED_ALLOW` → arrayrefs). Only `@mf_path`/`@cnf_path` stay global
  (search-path infrastructure used by `t/01`).
- **Test fallout:** `t/04-restricted.t` poked `$main::RESTRICTED` /
  `@main::RESTRICTED_ALLOW` and grepped the source for `unless $RESTRICTED`;
  updated to `$main::ctx->{cfg}{...}`.
- **Gate:** `t/06` colour/theme, `t/04` restricted policy, `t/07` CLI, full
  suite 311 green.

### Phase 5 — residual scalar runtime state
- `$SCREEN_DIR`, `$last_item_id`, `$pad_lines`, `$exec_args`, `$child_es`.
- `$cpid`/`$tmpfh` stay global (the SIGINT handler closure owns them) — document
  why rather than forcing them in.

### Phase 6 — capstone: modern pragma on `ccfe.pl`  *(the correctness payoff)*
- Only reachable once barewords are gone (group A imported, B/C on `$ctx`,
  remaining locals `my`-declared). Turn on strict+warnings, fix the fallout
  (undeclared vars, indirect-object calls, undef comparisons the no-strict code
  hid). Then tighten `.perlcriticrc` to lint `ccfe.pl` too, not just `src/lib`.
- **Feature level:** use **`use v5.36`** to match the existing `lib/CCFE/*`
  modules (it already gives strict + warnings + signatures + `say` — everything
  the capstone needs). A newer level (`v5.38`/`v5.40`) is fine if a specific
  feature ever justifies it; the version is not sacred. **Whatever level is
  chosen, `debian/control` must declare the matching `perl (>= X)`** in both
  `Depends` and `Build-Depends`.
- **Latent packaging gap to close here (or sooner):** the shipped 2.1.1 deb
  already requires Perl 5.36 (the `lib/CCFE/*` modules `use v5.36`) but
  `debian/control` still only says `perl` with no version bound. Add the
  `perl (>= 5.36.0)` floor as part of this phase — or pull it forward as a tiny
  standalone fix, since it is already technically under-specified today.

## 4. Where the value is — and where to stop

```
value  ████████████████  Phase 3 (%form / local removal)   ← ~70% of the win
       █████████         Phases 1–2 (field_vals, menu)
       ████              Phase 4 (cfg object)
       ███               Phase 6 (strict capstone, unlocks tighter gates)
       █                 Phases 0,5 (scaffolding, residue)
```

**Scope decision (agreed):** all phases **0–6 are in scope for M7** — the full
de-globalisation, finishing with the strict capstone. The value bars above set
the *order*, not the cut line: lead with Phase 3 (highest value), and treat 4–5
as required-but-lower-priority rather than optional.

**Stop-and-reassess gate:** still observe a checkpoint after Phase 3. If the
inner-sub conversion proves more invasive than the test coverage can safely
guard, pause and widen the tests before pressing on — the `local`-based code is
*correct and shipping*, so a half-threaded `%form` hybrid is worse than a clean
stop. De-globalisation is a quality investment, not a user-facing fix; it should
never trade away a working screen. (Per the agreed scope we resume to the end
once the checkpoint is clear; the gate is a safety valve, not the finish line.)

## 5. Effort / risk summary

| Phase | Surface | Risk | Notes |
|-------|---------|------|-------|
| 0 | scaffolding + ~120 consts | low | mechanical move |
| 1 | 8 sites + 3 inner subs | **med** | proves the nested-sub conversion |
| 2 | 38 sites | low–med | `load_menu` already returns a structure |
| 3 | ~160 sites + 7 inner subs | **high** | the core; split 3a/3b |
| 4 | ~30 vars | low–med | eval targets change shape |
| 5 | ~5 scalars | low | leave signal state global |
| 6 | whole file | med | strict fallout, one-time |

No new runtime dependencies; `$ctx` is a plain hashref. Each phase is its own
reviewable commit with the standard trailer, gated on the four CI checks.
