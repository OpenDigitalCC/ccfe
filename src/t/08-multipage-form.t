#!/usr/bin/perl
#
# Multi-page forms (ROADMAP M4).
#
# A form with more fields than fit on one screen is split into pages by
# libform; CCFE shows "Pg:N/M" and navigates with PgUp/PgDn.  The page change
# itself always worked, but libform does not repaint a derwin sub-window on a
# page switch, so the new page was invisible until redraw_form_page() forced a
# repaint.  This drives a 40-field form on a pseudo-terminal and asserts the
# pages actually display and navigate.
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

# A 40-field form -> several pages at 80x24.
my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/longform.form" ) or plan skip_all => "write: $!";
print {$fh} "title { Long form pagination test }\n";
for my $n ( 1 .. 40 ) {
    printf {$fh} "field {\n  id    = F%02d\n  len   = 5\n  type  = STRING\n"
      . "  label = Field number %02d\n}\n", $n, $n;
}
print {$fh} "action { run:true }\n";
close($fh);

plan tests => 5;

# The current page is the LAST "Pg:N/M" emitted into the stream.
sub curpage { my @m = $_[0]->screen =~ /Pg:(\d+\/\d+)/g; return $m[-1] // '?' }

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'longform' );
$pty->pump(1.3);
is( curpage($pty), '1/3', 'opens on page 1 of a 3-page form' );
like( $pty->screen, qr/Field number 01/, '  page 1 shows the first fields' );

$pty->send("\033[6~");    # Page Down
$pty->pump(1.0);
is( curpage($pty), '2/3', 'Page Down advances to page 2' );
like( $pty->screen, qr/Field number 18/,
    '  page 2 fields are actually painted' );

$pty->send("\033[5~");    # Page Up
$pty->pump(1.0);
is( curpage($pty), '1/3', 'Page Up returns to page 1' );

$pty->send("\033");
$pty->pump(0.3);
$pty->send("\033");
$pty->wait(3);
