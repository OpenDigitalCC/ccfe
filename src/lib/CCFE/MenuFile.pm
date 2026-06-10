package CCFE::MenuFile;

# Pure parser for CCFE `.menu` / `.item` content (ROADMAP M7, REFACTOR.md §3).
#
# parse($text) turns the (comment-stripped, concatenated) text of a menu --
# title/top/bottom/path blocks and any number of item blocks -- into a plain
# data structure the caller owns, with no terminal, no globals and no I/O.
# load_menu() in ccfe.pl keeps the file-finding/reading and copies the result
# into its %menu, so behaviour is unchanged; this module is what the parser
# tests drive directly.
#
# Returns ($menu, $status, \@warnings, $item_count):
#   $menu       = { title => str, top => [..], bottom => [..], path => str,
#                   items => [ { id => .., descr => .., action => .. }, .. ] }
#   $status     = 'ok' | 'syntax_error'   (an empty item list is the caller's
#                 concern -- it owns the "no items" status code)
#   warnings    = human-readable notes (duplicate id, unknown attribute, ...)
#                 the caller may trace()
#   item_count  = number of `item {}` blocks seen (a block with no recognised
#                 attribute still counts, matching the original parser)

use v5.36;
use Text::Balanced qw(extract_bracketed);

our $VERSION = '2.1';

# Top-level block keyword -> the menu field it sets.  Grouping the keywords
# this way keeps the dispatch flat instead of a long if/elsif cascade.
my %SCALAR_BLOCK = ( title => 'title', path   => 'path' );
my %LIST_BLOCK   = ( top   => 'top',   bottom => 'bottom' );

sub parse ($text) {
    my %menu = ( top => [], items => [] );
    my @warn;
    my $status = 'ok';
    my $ic     = 0;

    my ( $val, $key );
    ( $val, undef, $key ) = extract_bracketed( $text, '{', '\s*[a-zA-Z]+\s*' );
    while ($key) {
        $val =~ s/^\{\s*//;
        $val =~ s/\s*\n?\s*\}$//;
        $key =~ s/^\s+//;
        $key =~ s/\s+$//;
        my $k = lc $key;

        if ( $k eq 'item' ) {
            _parse_item( \%menu, $ic, $val, \@warn, \$status );
            $ic++;
        }
        elsif ( exists $SCALAR_BLOCK{$k} ) {
            $menu{ $SCALAR_BLOCK{$k} } = $val;
        }
        elsif ( exists $LIST_BLOCK{$k} ) {
            $menu{ $LIST_BLOCK{$k} } = [ split /\s*\n\s*/, $val, 2 ];
        }
        else {
            push @warn, "unknown menu attribute \"$key\"";
            $status = 'syntax_error';
        }

        ( $val, undef, $key ) =
          extract_bracketed( $text, '{', '\s*[a-zA-Z]+\s*' );
    }
    $status = 'syntax_error' if !pos($text);
    return ( \%menu, $status, \@warn, $ic );
}

# Parse one item block's `key = value` lines into $menu->{items}[$ic], warning
# on a duplicate id or an unknown attribute (and flagging a syntax error for the
# latter via the $status scalar ref).
sub _parse_item ( $menu, $ic, $val, $warn, $status ) {
    for my $line ( split /\s*\n\s*/, $val ) {
        my ( $ak, $av ) = split /\s*=\s*/, $line, 2;
        my $a = lc( $ak // '' );
        if ( $a eq 'id' ) {
            push @{$warn}, "duplicated item ID \"$av\""
              for grep { ( $menu->{items}[$_]{id} // '' ) eq $av } 0 .. $ic - 1;
            $menu->{items}[$ic]{id} = $av;
        }
        elsif ( $a eq 'descr' ) {
            $menu->{items}[$ic]{descr} = $av;
        }
        elsif ( $a eq 'action' ) {
            $menu->{items}[$ic]{action} = $av;
        }
        else {
            push @{$warn}, "unknown item attribute \"$ak\"";
            ${$status} = 'syntax_error';
        }
    }
    return;
}

1;
