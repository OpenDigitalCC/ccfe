#!/usr/bin/perl
#
# A long menu top{} message must force vertical space (the menu is drawn below
# the full message) rather than being overdrawn by the menu.
#
# Regression: a menu whose top{} wrapped to more than the fixed 2-row top area
# collided with the centred menu -- the menu sub-window was drawn over the last
# line(s) of the description (truncating it) and the items appeared mid-text.
# The top area is now sized to the wrapped message height. This drives a menu
# with a 3-line top and asserts both the full message and the items render.
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/lib";
use File::Temp qw(tempdir);
use Test::More;

my $src = "$Bin/..";

eval { require CCFE::Test::Pty; 1 } or plan skip_all => "pty helper: $@";
plan skip_all => 'no Linux pseudo-terminal' unless CCFE::Test::Pty->available;
plan skip_all => 'Curses not installed'     unless eval { require Curses; 1 };
plan skip_all => 'no installer' unless -f "$src/install.sh";

my $prefix = tempdir( CLEANUP => 1 );
my $log    = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
plan skip_all => "install failed: $log" unless $? == 0 && -x "$prefix/bin/ccfe";

my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/longtop.menu" ) or plan skip_all => "write: $!";
print {$fh} <<'MENU';
title { Long top test }
top {
  This is a deliberately long first line of the menu top description text.
  Here is a second explanatory line that also runs a fair way across.
  Third line ending with a distinctive marker word ZZEND that must survive.
}
item {
  id     = ALPHA
  descr  = First item ALPHAITEM
  action = run:true
}
item {
  id     = OMEGA
  descr  = Last item OMEGAITEM
  action = run:true
}
MENU
close($fh);

plan tests => 3;

# Wide terminal -- the original collision was worst when the centred menu sat
# under a top message wider than the 2-row budget.
my $pty = CCFE::Test::Pty->spawn( 120, 30, "$prefix/bin/ccfe", 'longtop' );
$pty->pump(1.3);
my $screen = $pty->screen;

like( $screen, qr/ZZEND/,
    'the full top message survives (last line not overdrawn by the menu)' );
like( $screen, qr/ALPHAITEM/, 'the first menu item renders' );
like( $screen, qr/OMEGAITEM/, '  ... and the last menu item renders too' );

$pty->send("\e");
$pty->pump(0.2);
$pty->send("\e");
