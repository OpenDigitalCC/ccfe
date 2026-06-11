package CCFE::Config;

# Pure tokenizer for CCFE `.conf` content (ROADMAP M7, REFACTOR.md §3).
#
# parse($text) walks the top-level `SECTION { ... }` blocks of an already
# comment-stripped config and returns them in file order as a plain list, with
# no terminal, no globals and no I/O.  load_config() in ccfe.pl keeps the file
# finding/reading/comment-stripping and owns the (heavily effectful,
# scope-bound) dispatch: validating each section's `key = value` lines and
# assigning the program globals -- including the `eval "$VAR = ..."` colour and
# attribute settings, which must run in ccfe.pl's own package to see its colour
# helpers and curses constants, and the term-specific (`FIELD_ATTR.$TERM`) and
# $COLS-dependent handling.  So this module is just the section walk -- the one
# genuinely pure, duplicated-three-ways piece -- and its tests drive it
# directly.
#
# Returns ($sections, $status, \@warnings):
#   $sections = [ { name => 'GLOBAL', body => "KEY = val\n..." }, ... ] in file
#               order.  A section may legitimately repeat; the caller applies
#               each in turn.  `name` keeps the file's case (e.g.
#               "FIELD_ATTR.xterm"); the caller upper-cases for matching.
#   $status   = 'ok' | 'syntax_error'   ('syntax_error' only for an
#               unterminated bracket walk; an unknown section or key is the
#               caller's concern, since it owns the dispatch)
#   warnings  = kept for shape-consistency with the other parsers (empty here)

use v5.36;
use Text::Balanced qw(extract_bracketed);

our $VERSION = '2.1';

sub parse ($text) {
    my @sections;
    my @warn;
    my $status = 'ok';

    my ( $val, $key );
    ( $val, undef, $key ) =
      extract_bracketed( $text, '{', '\s*[a-zA-Z_\.]+\s*' );
    while ($key) {
        $val =~ s/^\{\s*//;
        $val =~ s/\s*\n?\s*\}$//;
        $key =~ s/^\s+//;
        $key =~ s/\s+$//;
        push @sections, { name => $key, body => $val };
        ( $val, undef, $key ) =
          extract_bracketed( $text, '{', '\s*[a-zA-Z_\.]+\s*' );
    }
    $status = 'syntax_error' if !pos($text);
    return ( \@sections, $status, \@warn );
}

1;

__END__

=head1 NAME

CCFE::Config - pure tokenizer for CCFE F<.conf> content

=head1 SYNOPSIS

    use CCFE::Config;
    my ($sections, $status, $warnings) = CCFE::Config::parse($conf_text);
    for my $s (@$sections) {
        # $s->{name} e.g. 'GLOBAL', 'FIELD_ATTR.xterm'
        # $s->{body} the "KEY = val" lines inside the braces
    }

=head1 DESCRIPTION

Walks the top-level C<< SECTION { ... } >> blocks of an already
comment-stripped config and returns them in file order, with no terminal, no
globals and no I/O. C<load_config> in F<ccfe.pl> keeps the file
finding/reading/comment-stripping and owns the heavily effectful, scope-bound
dispatch (validating each section's C<key = value> lines and assigning the
program globals, including the colour/attribute settings that must run in
F<ccfe.pl>'s own package, and the term-specific C<FIELD_ATTR.$TERM> and
C<$COLS>-dependent handling). This module is just the section walk - the one
genuinely pure, formerly-duplicated piece.

=head1 FUNCTIONS

=head2 parse

    my ($sections, $status, $warnings) = CCFE::Config::parse($text);

Returns a three-element list:

=over 4

=item C<$sections>

An arrayref of C<< { name => 'GLOBAL', body => "KEY = val\n..." } >> in file
order. A section may legitimately repeat; the caller applies each in turn.
C<name> keeps the file's case (e.g. C<FIELD_ATTR.xterm>); the caller
upper-cases for matching.

=item C<$status>

C<'ok'> or C<'syntax_error'>. C<'syntax_error'> is reported only for an
unterminated bracket walk; an unknown section or key is the caller's concern,
since it owns the dispatch.

=item C<$warnings>

An arrayref, kept for shape-consistency with the other parsers (always empty
here).

=back

=head1 SEE ALSO

L<ccfe.conf(5)>, F<REFACTOR.md> section 3.

=cut
