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

__END__

=head1 NAME

CCFE::Context - the CCFE run-state container

=head1 SYNOPSIS

    use CCFE::Context;
    my $ctx = CCFE::Context::new();
    $ctx->{cfg}{RESTRICTED}   = 1;
    $ctx->{state}{SCREEN_DIR} = $dir;

=head1 DESCRIPTION

De-globalisation (ROADMAP M7) replaces F<ccfe.pl>'s package globals and C<local>
dynamic scope with one explicit state object, threaded through the screen subs
instead of being read and written at a distance. This module is that object's
single home: a plain, deliberately unblessed hashref (callers use
C<< $ctx->{...} >> directly) built once at startup and passed down the call
chain.

The object has two top-level keys:

=over 4

=item C<cfg>

Configuration settings, filled by C<load_config>.

=item C<state>

Mutable shared run-state (the current screen directory, the last selected item,
output-pad line counts, pending exec arguments, the child exit status, and so
on).

=back

Per-screen run state (field values, the menu/form structures, field pointers)
is deliberately B<not> kept on the context: it stays in per-call lexicals so
nested-screen recursion keeps the old C<local> semantics.

=head1 FUNCTIONS

=head2 new

    my $ctx = CCFE::Context::new();

Returns a fresh container, C<< { cfg => {}, state => {} } >>. Takes no
arguments. The two sub-hashes are seeded so C<load_config> and the run-state
readers can assume they exist.

=head1 SEE ALSO

L<ccfe(1)>, F<REFACTOR.md> section 3.2.

=cut
