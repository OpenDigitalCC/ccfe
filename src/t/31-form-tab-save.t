#!/usr/bin/perl
#
# do_form TAB value-cycling and the Save key -- event-loop coverage (TD-2),
# extending the net before the do_form event-loop extraction.
#
# Two branches with their own logic, neither exercised before:
#   * TAB / Shift-TAB on a field with a `const:single-val` list_cmd cycles the
#     field through the list's values in place (no chooser pops): empty -> first
#     value, then to the next, wrapping round. This is the ~50-line TAB arm.
#   * The Save key syncs the field values, logs them, and shows a confirmation
#     ("Fields value saved in log file.").
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
open( my $fh, '>', "$objs/tab.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Tab test }
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

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'tab' );
$pty->pump(1.3);

# TAB cycles the empty field to the first list value in place (no chooser).
# Read the value back functionally via the F5 action preview, which syncs the
# field buffers and substitutes %{COLOUR} -- robust against where the field
# cell happens to render.
$pty->send("\t");          # cycle: (empty) -> red
$pty->pump(0.4);
$pty->send("\e[15~");      # F5 preview
$pty->pump(0.6);
like( $pty->screen, qr/PICKED-red/,
    'TAB cycles the field to the first value (preview shows red)' );
$pty->send("\e");          # close the preview list
$pty->pump(0.3);

# TAB again advances to the next value.
$pty->send("\t");          # cycle: red -> green
$pty->pump(0.4);
$pty->send("\e[15~");      # F5 preview
$pty->pump(0.6);
like( $pty->screen, qr/PICKED-green/,
    '  a second TAB advances to the next value (preview shows green)' );
$pty->send("\e");          # close the preview list
$pty->pump(0.3);

# Save (F6) logs the field values and confirms.
$pty->send("\e[17~");
$pty->pump(0.6);
like( $pty->screen, qr/saved in log file/,
    'the Save key logs the field values and confirms' );

$pty->send("\r");    # dismiss the confirmation
$pty->pump(0.3);
$pty->send("\e");
