#!/usr/bin/perl
#
# do_form value-list (F2) and action preview (F5) -- event-loop coverage (TD-2),
# strengthening the net before the do_form event-loop extraction.
#
# F2 (list) on a field with a list_cmd pops a chooser of the command's items and
# fills the field with the chosen value; F5 (show_action) resolves the form's
# action -- syncing the field values and substituting %{ID} -- and shows it.
# Neither was tested (t/23 covers only the empty-list F2 case). This drives both
# end to end: pick a value from the list, then preview the action and check the
# picked value was substituted in.
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
open( my $fh, '>', "$objs/keys.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Keys test }
field {
  id       = COLOUR
  len      = 20
  type     = STRING
  label    = Colour
  list_cmd = const:single-val:"red A red one","green A green one"
}
action { run:echo PICKED-%{COLOUR} }
FORM
close($fh);

plan tests => 3;

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'keys' );
$pty->pump(1.3);

# F2 = list: the value chooser pops with the list_cmd's items.
$pty->send("\eOQ");
$pty->pump(0.8);
like( $pty->screen, qr/A red one|A green one/,
    'F2 opens the value list from list_cmd' );

# pick the first item (red) -> fills the field
$pty->send("\r");
$pty->pump(0.8);
like( $pty->screen, qr/\bred\b/, '  choosing an item fills the field' );

# F5 = show_action: resolves the action with the chosen value substituted.
$pty->send("\e[15~");
$pty->pump(0.8);
like( $pty->screen, qr/PICKED-red/,
    'F5 previews the resolved action (%{COLOUR} -> red)' );

$pty->send("\r");
$pty->pump(0.3);
$pty->send("\e");
