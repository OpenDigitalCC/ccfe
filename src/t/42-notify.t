#!/usr/bin/perl
#
# Notifications display (FEATURE-REQUESTS D1, minimal file-poll version).
#
# When `notify_file` names a non-empty file, its contents are shown as a pop-up
# banner each time a menu screen is entered, and each distinct write is shown
# once.  This drives both: the banner appears on the first menu, and after the
# file is rewritten a fresh banner appears on entering a child menu.
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

my $nfile = "$prefix/notify.txt";
open( my $nf, '>', $nfile ) or plan skip_all => "notify: $!";
print {$nf} "NOTIFYBANNERMARK";
close($nf);

my $conf = "$prefix/etc/ccfe.conf";
open( my $cf, '>>', $conf ) or plan skip_all => "conf: $!";
print {$cf} "\nglobal {\n  notify_file = $nfile\n}\n";
close($cf);

my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $m1, '>', "$objs/notifytest.menu" ) or plan skip_all => "write: $!";
print {$m1} <<'MENU';
title { Notify test }
item {
  id     = GO
  descr  = Go to child
  action = menu:child
}
MENU
close($m1);

open( my $m2, '>', "$objs/child.menu" ) or plan skip_all => "write: $!";
print {$m2} <<'MENU';
title { Child menu }
item {
  id     = X
  descr  = Nothing
  action = run:true
}
MENU
close($m2);

plan tests => 2;

my $p = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'notifytest' );
$p->pump(1.3);
like( $p->screen, qr/NOTIFYBANNERMARK/,
    'a pending notification is shown on entering the menu' );
$p->send(" ");    # dismiss the banner
$p->pump(0.5);

# A fresh write (different size) is a new notification; entering the child menu
# surfaces it.
open( my $nf2, '>', $nfile ) or die "notify rewrite: $!";
print {$nf2} "NEWNOTIFYMARK";
close($nf2);

$p->send("\r");    # GO -> child menu -> check on entry
$p->pump(1.0);
like( $p->screen, qr/NEWNOTIFYMARK/,
    'a fresh write is surfaced on the next menu entry' );
$p->send(" ");     # dismiss
$p->pump(0.3);
$p->send("\e");
$p->pump(0.2);
$p->send("\e");
$p->pump(0.2);
