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
