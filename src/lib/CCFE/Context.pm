package CCFE::Context;

# The CCFE run-state container (ROADMAP M7, REFACTOR.md §3.2).
#
# De-globalisation replaces ccfe.pl's package globals and `local` dynamic scope
# with one explicit state object, threaded through the screen subs instead of
# read/written at a distance.  This module is that object's single home: a plain
# hashref (deliberately not blessed -- callers use $ctx->{...} directly) built
# once at startup and passed down the call chain.
#
# It is introduced empty in Phase 0; each later phase moves one structure onto
# it so the change is mechanical and test-gated, never a big-bang rewrite:
#
#   cfg        config settings filled by load_config           (Phase 4)
#   state      mutable shared run-state (current screen dir,    (Phase 5)
#              last selected item, output-pad lines, ...)
#   field_vals / menu / form / fp / ...   per-screen run state  (Phases 1-3,
#              held as per-call lexicals, not on $ctx -- see the plan)
#
# Centralising construction means a future fresh/child context -- the explicit
# replacement for the `local %form/%menu/...` nested-screen recursion -- has one
# place to live.

use v5.36;

our $VERSION = '2.1.1';

# Return a fresh, empty run-state container.  The cfg and state sub-hashes are
# seeded so load_config (Phase 4) and the run-state readers (Phase 5) can assume
# they exist.
sub new {
    return { cfg => {}, state => {} };
}

1;
