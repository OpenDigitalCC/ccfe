#!/usr/bin/perl
#
# Issue #1 end-to-end regression (TD-2): pressing the list key (F2) on a field
# whose list_cmd yields nothing must NOT crash.
#
# Root cause (fixed in v1.60): do_list() built a curses menu from an empty item
# list; with no items, item_index(current_item(...)) dies / segfaults on some
# ncurses builds. The empty list reached do_list when a field's list_cmd
# produced no items. t/02 pins the source-level guards; this drives the actual
# repro now that the pty harness exists -- F2 on an empty-list field -- and
# asserts CCFE shows the graceful "empty list" message and keeps running
# instead of dying.
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

# A field whose list command produces no items (`true` exits 0 with no output).
my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/emptylist.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Empty list test }
field {
  id       = PICK
  len      = 10
  type     = STRING
  label    = Pick
  list_cmd = command:single-val:true
}
action { run:true }
FORM
close($fh);

plan tests => 2;

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'emptylist' );
$pty->pump(1.2);
like( $pty->screen, qr/Pick/, 'the form opens with the list field' );

$pty->send("\eOQ");    # F2 = list, on the (focused) empty-list field
$pty->pump(1.0);

# It must reach the graceful empty/null-list message, not crash. (If it had
# segfaulted, the child would be gone and the screen would not show this.)
like(
    $pty->screen,
    qr/Nothing to choose from|list not available/,
    'F2 on an empty-list field shows the graceful message (no crash)'
);

$pty->send("\r");    # dismiss the message
$pty->pump(0.2);
$pty->send("\e");    # leave the form
