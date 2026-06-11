#!/usr/bin/perl
#
# exec: action with a missing command -> a clear pop-up, not an opaque exit
# (FEATURE-REQUESTS item 6).
#
# The exec: verb tears curses down and replaces the process; if the command is
# not found the exec fails and ccfe would just exit, leaving a cleared terminal
# with no explanation. A pre-flight check now shows a "command not found"
# pop-up while the TUI is still up, and refuses to exec. A command that *does*
# exist must not trip the check.
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

open( my $bad, '>', "$objs/execbad.menu" ) or plan skip_all => "menu: $!";
print {$bad} <<'MENU';
title { Exec bad }
item {
  id     = X
  descr  = run a missing program
  action = exec:ccfe-definitely-no-such-prog-xyzzy
}
MENU
close($bad);

open( my $good, '>', "$objs/execok.menu" ) or plan skip_all => "menu: $!";
print {$good} <<'MENU';
title { Exec ok }
item {
  id     = X
  descr  = run a real program
  action = exec:true
}
MENU
close($good);

plan tests => 3;

# --- missing command: pop-up, and we are still in the TUI ----------------
my $p = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'execbad' );
$p->pump(1.2);
$p->send("\r");    # activate the item -> exec: pre-flight check
$p->pump(0.8);
like( $p->screen, qr/not found or not executable|COMMAND NOT FOUND/i,
    'a missing exec: command shows a "command not found" pop-up' );
$p->send("\r");    # dismiss the pop-up
$p->pump(0.4);
like( $p->screen, qr/run a missing program/,
    '  ... and ccfe stays in the menu rather than exiting opaquely' );
$p->send("\e");
$p->pump(0.3);

# --- valid command: no false positive ------------------------------------
my $p2 = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'execok' );
$p2->pump(1.2);
$p2->send("\r");    # activate -> exec: 'true' (exists) -> ccfe execs it
$p2->pump(0.8);
unlike( $p2->screen, qr/not found or not executable|COMMAND NOT FOUND/i,
    'a real command does not trip the not-found check' );
$p2->send("\e");
$p2->pump(0.3);
