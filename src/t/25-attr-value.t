#!/usr/bin/perl
#
# attr_value(): eval-free parsing of config *_attr values (TD-1d).
#
# Colour/attribute config settings used to be applied with
# `eval "$VAR = <config value>"`, which executes arbitrary Perl from the config
# file. attr_value() replaces that with a parser for the documented grammar
# (A_* / COLOR_PAIR(n) / color_pair('fg','bg') / integer / `|`-combinations).
# This checks it resolves valid values correctly AND refuses -- without
# executing -- anything outside the grammar.
#
use strict;
use warnings;
use FindBin qw($Bin);
use Test::More;

my $src = "$Bin/..";
$ENV{CCFE_TESTING} = 1;
eval { require "$src/ccfe.pl"; 1 } or plan skip_all => "cannot load ccfe.pl: $@";
plan skip_all => 'Curses not usable headlessly'
  unless eval { Curses::A_BOLD(); 1 };

no warnings 'once';

# ---- valid grammar ------------------------------------------------------
is( main::attr_value('A_BOLD'), Curses::A_BOLD(), 'A_BOLD resolves' );
is( main::attr_value('A_NORMAL'), Curses::A_NORMAL(), 'A_NORMAL resolves' );
is(
    main::attr_value('A_BOLD | A_REVERSE'),
    ( Curses::A_BOLD() | Curses::A_REVERSE() ),
    'a `|`-combination ORs the attributes'
);
is( main::attr_value('COLOR_PAIR(3)'),
    Curses::COLOR_PAIR(3), 'COLOR_PAIR(n) resolves' );
is( main::attr_value('7'),  7,     'a bare integer resolves' );
is( main::attr_value(''),   undef, 'empty value -> undef' );
is( main::attr_value(undef), undef, 'undef value -> undef' );

# color_pair('fg','bg') resolves to a number (allocates a pair)
ok( defined main::attr_value("color_pair('white','blue')"),
    "color_pair('fg','bg') resolves" );

# ---- injection is refused AND not executed ------------------------------
my $marker = "/tmp/ccfe-attr-pwned-$$";
unlink $marker;
for my $payload (
    qq{0; system("touch $marker")},
    qq{0; `touch $marker`},
    qq{\@{[ system("touch $marker") ]}},
    'system("id")',
    'A_BOLD; warn "x"',
  )
{
    is( main::attr_value($payload), undef, "refused: $payload" );
}
ok( !-e $marker, 'no injection payload executed (no side-effect file)' );
unlink $marker;

done_testing();
