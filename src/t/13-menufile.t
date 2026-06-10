#!/usr/bin/perl
#
# Unit tests for the pure CCFE::MenuFile parser (ROADMAP M7).
#
# The .menu/.item bracket parser was lifted out of load_menu() into a pure,
# terminal-free module so it can be exercised directly -- no install, no pty,
# no globals.  These drive parse($text) and check the returned data structure,
# status and warnings.
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

require_ok('CCFE::MenuFile') or BAIL_OUT('cannot load CCFE::MenuFile');

# ---- a well-formed menu -------------------------------------------------
my ( $m, $st, $w, $ic ) = CCFE::MenuFile::parse( <<'EOT');
title { My menu }
top { line one
line two }
item {
  id     = A
  descr  = first thing
  action = run:ls
}
item {
  id     = B
  descr  = second thing
  action = menu:sub
}
bottom { footer }
EOT

is( $st, 'ok', 'a well-formed menu parses with status ok' );
is( $ic, 2,    '  two item blocks counted' );
is( $m->{title}, 'My menu', '  title captured' );
is_deeply( $m->{top}, [ 'line one', 'line two' ],
    '  top split into its lines' );
is_deeply( $m->{bottom}, ['footer'], '  bottom captured' );
is( scalar @{ $m->{items} }, 2,        '  two items' );
is( $m->{items}[0]{id},      'A',      '  item 0 id' );
is( $m->{items}[0]{descr},   'first thing', '  item 0 descr' );
is( $m->{items}[0]{action},  'run:ls', '  item 0 action' );
is( $m->{items}[1]{action},  'menu:sub', '  item 1 action' );
is_deeply( $w, [], '  no warnings' );

# ---- duplicate item id warns but still parses ---------------------------
( $m, $st, $w, $ic ) = CCFE::MenuFile::parse(
    "item { id = X\naction = run:a }\nitem { id = X\naction = run:b }\n");
is( $ic, 2, 'duplicate id: both items kept' );
like( "@{$w}", qr/duplicated item ID "X"/, '  duplicate id is warned' );

# ---- an unknown attribute is a syntax error -----------------------------
( $m, $st, $w, $ic ) =
  CCFE::MenuFile::parse("item {\n  id = A\n  bogus = 1\n}\n");
is( $st, 'syntax_error', 'unknown item attribute -> syntax_error' );
like( "@{$w}", qr/unknown item attribute "bogus"/, '  and is warned' );

( $m, $st, $w, $ic ) = CCFE::MenuFile::parse("weird { stuff }\n");
is( $st, 'syntax_error', 'unknown top-level block -> syntax_error' );

# ---- empty input: no items, defensive empty arrays ----------------------
( $m, $st, $w, $ic ) = CCFE::MenuFile::parse('');
is( $ic, 0, 'empty input: zero items' );
is_deeply( $m->{items}, [], '  items is an empty array (not undef)' );
is_deeply( $m->{top},   [], '  top is an empty array (not undef)' );

done_testing();
