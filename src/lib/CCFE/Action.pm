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
