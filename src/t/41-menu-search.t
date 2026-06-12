#!/usr/bin/perl
#
# Object search across the menu/form path (FEATURE-REQUESTS B1).
#
# The `search:` action prompts for a pattern, scans every menu/form on the
# search path (titles, top/bottom text, item descriptions, form field labels)
# and offers the matches in a pop-up; opening one jumps to that object.  This
# drives it end to end: search a word that appears only in one form's title,
# confirm the form is listed, open it and confirm its field label renders.
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

# The object to find: a unique word in its title, a unique field label.
open( my $ff, '>', "$objs/findme.form" ) or plan skip_all => "write: $!";
print {$ff} <<'FORM';
title { Findme ZEBRACROSSING }
field {
  id    = X
  label = OPENEDFORMMARK
  len   = 10
}
action { run:true }
FORM
close($ff);

open( my $mf, '>', "$objs/searchtest.menu" ) or plan skip_all => "write: $!";
print {$mf} <<'MENU';
title { Search test }
item {
  id     = SEARCH
  descr  = Search
  action = search:
}
MENU
close($mf);

plan tests => 2;

my $p = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'searchtest' );
$p->pump(1.2);

$p->send("\r");    # SEARCH item -> pattern prompt
$p->pump(0.7);
$p->send("ZEBRA");
$p->pump(0.4);
$p->send("\r");    # submit -> results list
$p->pump(0.9);
like( $p->screen, qr/findme/,
    'the form is found by a word in its title' );

$p->send("\r");    # open the (only) match
$p->pump(0.9);
like( $p->screen, qr/OPENEDFORMMARK/,
    'opening a result jumps to that object' );

$p->send("\e");
$p->pump(0.2);
$p->send("\e");
$p->pump(0.2);
$p->send("\e");
$p->pump(0.2);
