package CCFE::Action;

# Pure parser for a CCFE action string (ROADMAP M7, REFACTOR.md §3).
#
# An action string is `VERB[(opt,opt,...)]:ARGS` -- e.g. "run:ls -l",
# "menu:submenu", "system(confirm,wait_key):reboot".  parse() splits it into
# its verb, its option list and its raw argument string, with no terminal and
# no globals.  do_menu()/do_form() in ccfe.pl own the dispatch -- running the
# verb, prompting for `confirm`, honouring `log`/`wait_key` -- which is
# effectful (it draws confirmation lists and spawns commands) and stays there.
# This was the same five-line parse duplicated at both call sites.
#
# parse($str) returns a hashref:
#   { verb => 'run',              # lower-cased; undef if the head is malformed
#     opts => [ 'confirm', ... ], # option names, in order (possibly empty)
#     args => 'ls -l' }           # everything after the first ':', verbatim
#                                 # (undef if the string carried no ':')
#
# The head is leading-whitespace-trimmed before matching (as do_form already
# did, and a no-op for menu actions, which the .menu parser trims).  A head
# that is not `word` or `word(opts)` yields verb => undef, opts => [] -- the
# caller's verb dispatch then simply finds no match, exactly as before.

use v5.36;

our $VERSION = '2.1';

sub parse ($str) {
    my ( $head, $args ) = split /:/, $str // '', 2;
    $head //= '';
    $head =~ s/^\s+//;
    $head = lc $head;

    my ( $verb, $optstr );
    if ( $head =~ /^([a-zA-Z]+)\(?([a-zA-Z_,]*)\)?$/ ) {
        $verb   = $1;
        $optstr = $2;
    }
    my @opts = defined $optstr ? split( /,\s*/, $optstr ) : ();
    return { verb => $verb, opts => \@opts, args => $args };
}

1;

__END__

=head1 NAME

CCFE::Action - pure parser for a CCFE action string

=head1 SYNOPSIS

    use CCFE::Action;
    my $act = CCFE::Action::parse('system(confirm,wait_key):reboot');
    # $act = { verb => 'system',
    #          opts => [ 'confirm', 'wait_key' ],
    #          args => 'reboot' }

=head1 DESCRIPTION

An action string is C<< VERB[(opt,opt,...)]:ARGS >> - for example C<run:ls -l>,
C<menu:submenu>, C<system(confirm,wait_key):reboot>. This module splits one into
its verb, option list and raw argument string, with no terminal and no globals.
C<do_menu>/C<do_form> in F<ccfe.pl> own the dispatch - running the verb,
prompting for C<confirm>, honouring C<log>/C<wait_key> - which is effectful and
stays there. The parse was previously duplicated at both call sites.

=head1 FUNCTIONS

=head2 parse

    my $act = CCFE::Action::parse($str);

Returns a hashref:

=over 4

=item C<verb>

The lower-cased verb, or C<undef> if the head is malformed.

=item C<opts>

An arrayref of option names, in order (possibly empty).

=item C<args>

Everything after the first C<:>, verbatim; C<undef> if the string carried no
C<:>.

=back

The head is leading-whitespace-trimmed before matching. A head that is not
C<word> or C<word(opts)> yields C<< verb => undef, opts => [] >>, so the caller's
verb dispatch simply finds no match - exactly the previous behaviour.

=head1 SEE ALSO

L<ccfe_menu(5)>, L<ccfe_form(5)>, F<REFACTOR.md> section 3.

=cut
