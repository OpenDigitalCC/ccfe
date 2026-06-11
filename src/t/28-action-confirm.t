#!/usr/bin/perl
#
# Action `confirm` option (TD-2 coverage; guards the TD-3 opts de-dup).
#
# An action with the `confirm` option pops a Yes/No list before running; No
# aborts it. This path (do_menu/do_form -> the confirm do_list) was untested.
# Driving it both fixes the gap and pins the behaviour before the confirm/log/
# wait_key opts handling is shared between do_menu and do_form.
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
open( my $mf, '>', "$objs/cmenu.menu" ) or plan skip_all => "menu: $!";
print {$mf} <<'MENU';
title { Confirm test }
item {
  id     = T
  descr  = do it
  action = run(confirm): printf 'CONFIRMED_RAN\n'
}
MENU
close($mf);

plan tests => 3;

# --- decline: No aborts the action --------------------------------------
my $p = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'cmenu' );
$p->pump(1.2);
$p->send("\r");    # activate -> confirm Yes/No list pops
$p->pump(0.8);
like( $p->screen, qr/Confirm and continue|Abort and return/,
    'confirm opens a Yes/No chooser' );
# default selection is No -> Enter declines
$p->send("\r");
$p->pump(0.8);
unlike( $p->screen, qr/CONFIRMED_RAN/,
    'declining the confirmation does not run the action' );
$p->send("\e");
$p->pump(0.3);

# --- accept: choosing Yes runs it ---------------------------------------
my $p2 = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'cmenu' );
$p2->pump(1.2);
$p2->send("\r");        # activate -> confirm list
$p2->pump(0.8);
$p2->send("\eOB");      # down-arrow (application mode) to the YES item
$p2->pump(0.3);
$p2->send("\r");        # accept
$p2->pump(1.0);
like( $p2->screen, qr/CONFIRMED_RAN/,
    'confirming with Yes runs the action' );
$p2->send(" ");
$p2->pump(0.2);
$p2->send("\e");
