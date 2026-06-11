# `CCFE::*` — the extracted modules

This directory holds the parts of CCFE that have been lifted out of the single
`src/ccfe.pl` program into small, focused modules. It is the result of the M7
de-globalisation work (see `REFACTOR.md` and `ROADMAP.md` at the repo root).

## Why these exist

`ccfe.pl` is a large, legacy, intentionally un-`strict` Perl/Curses program. It
stays that way on purpose — it is the interactive shell that owns the terminal,
the windows, the event loops and all the side effects. What has been pulled out
here is the opposite: the **pure functional core** — the parsing and geometry
that take data in and give data back with *no terminal, no globals and no I/O*.

That split buys two things:

- **Testability.** A pure function can be unit-tested without a pty or curses
  (`t/13`–`t/18`, `t/25` exercise these directly). The interactive paths are
  covered separately by the pty harness (`t/lib/CCFE/Test/Pty.pm`).
- **De-duplication.** Several of these were the same logic written out at two or
  three call sites in `ccfe.pl` (e.g. the form geometry used by both initial
  layout and resize). The module is now the single home; `ccfe.pl` calls it.

New code here targets modern Perl: every module is `use v5.36` (strict,
warnings, subroutine signatures, `say`), so the legacy main program does not
constrain the style of freshly written code.

## Module map

| Module | What it is | `ccfe.pl` caller |
|--------|------------|------------------|
| `Context.pm`  | The run-state container: one unblessed `{ cfg, state }` hashref threaded through the screen subs instead of package globals. | built at startup, passed everywhere as `$ctx` |
| `Config.pm`   | Pure tokenizer that walks a `.conf` into its `SECTION { ... }` blocks in file order. | `load_config` |
| `MenuFile.pm` | Pure parser: `.menu`/`.item` text → menu/items data structure. | `load_menu` |
| `FormFile.pm` | Pure parser: `.form` text → form/fields data structure. | `load_form` |
| `Action.pm`   | Pure parser for an action string `VERB[(opts)]:ARGS`. | `do_menu` / `do_form` dispatch |
| `Layout.pm`   | Pure form geometry: value-column placement and page-break arithmetic. | `do_form` initial layout and `resize_form` |
| `Restrict.pm` | Pure restricted-/kiosk-mode policy: which verbs and the shell escape are refused, plus env hardening and shell quoting. | the `restricted_denies_*` helpers |
| `Theme.pm`    | Optional colour: pre-creates `COLOR_PAIR(n)` over the default background so `*_attr` config can reference colour. The one effectful piece (`init_pair`) runs after `start_color()`. | colour set-up at startup |

Each module carries full POD — `perldoc CCFE::FormFile` (etc.) for the
function-level reference. The boundary in every case is the same: **the module
parses or computes; `ccfe.pl` keeps the file I/O, the curses calls and the
dispatch.**

## What is *not* here

Per-screen run state (the live `%form`/`%menu`, the field-pointer arrays, the
field-value map) is **not** on `Context` and **not** in a module — it stays in
per-call lexicals inside `ccfe.pl`'s `do_form`/`do_menu`, so nested-screen
recursion keeps the old `local`-scoped semantics. See `M7-CTX-PLAN.md`.

## Conventions for new modules

- `use v5.36;` and an `our $VERSION`.
- Pure where possible: take what you need as arguments, return data; let
  `ccfe.pl` keep the side effects. If you must touch curses, isolate it in one
  clearly-named effectful function (as `Theme::init_standard_pairs` does).
- Add POD (`=head1 NAME/SYNOPSIS/DESCRIPTION/FUNCTIONS/SEE ALSO`).
- Add a `t/NN-<name>.t` that drives the pure functions directly.
- The CI gate covers `src/lib` (but **not** `ccfe.pl`): `perl -c`,
  `prove -lr t/`, `perlcritic --profile .perlcriticrc src/lib`, and perltidy on
  `src/lib`. Keep all four green.
