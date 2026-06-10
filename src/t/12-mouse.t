#!/usr/bin/perl
#
# Opt-in mouse support (ROADMAP M6).
#
# With `mouse = YES` in the config, do_menu grabs left clicks: a single click
# moves the selection to the clicked item, a double click activates it (same as
# Enter).  This drives a menu on a pseudo-terminal, injects SGR mouse events,
# and checks a double-click on a menu item runs its action (here: opens a form).
# Mouse stays off by default, so this needs the config flag set.
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
plan skip_all => 'no mouse support in this Curses'
  unless Curses->can('getmouse') && Curses->can('mousemask');

my $prefix = tempdir( CLEANUP => 1 );
my $log    = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
plan skip_all => "install failed: $log" unless $? == 0 && -x "$prefix/bin/ccfe";

plan tests => 3;

my $objs = "$prefix/share/ccfe/objects/ccfe";

# A menu whose first item opens a form with a recognisable title.
open( my $fh, '>', "$objs/mtest.menu" ) or die "write: $!";
print {$fh} "title { Mouse menu }\n";
print {$fh} "item {\n  id     = OPEN\n  descr  = Open the form\n"
  . "  action = form:mtest.d/mform\n}\n";
print {$fh} "item {\n  id     = SECOND\n  descr  = A second item\n"
  . "  action = run:true\n}\n";
close($fh);
mkdir "$objs/mtest.d";
open( $fh, '>', "$objs/mtest.d/mform.form" ) or die "write: $!";
print {$fh} "title { MOUSEFORM }\n";
print {$fh} "field {\n  id    = A\n  len   = 5\n  type  = STRING\n"
  . "  label = Clicked open\n}\n";
print {$fh} "action { run:true }\n";
close($fh);

# Turn the mouse on for this instance.
my $conf = "$prefix/etc/ccfe.conf";
open( $fh, '>>', $conf ) or die "conf: $!";
print {$fh} "\nglobal {\n  mouse = YES\n}\n";
close($fh);

# A left double-click on the first menu item.  Items start at screen row
# MS_HEADER_ROWS + MS_TOP_ROWS = 4 (0-based), so the first item is SGR row 5.
# SGR mouse: ESC [ < button ; col ; row M  (press) / m (release).
sub sgr_click {
    my ( $pty, $col, $row ) = @_;
    $pty->send("\x1b[<0;$col;${row}M");
    $pty->send("\x1b[<0;$col;${row}m");
}

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'mtest' );
$pty->pump(1.3);
like( $pty->screen, qr/Mouse menu/, 'menu rendered with mouse enabled' );

# double-click the first item (col 20, SGR row 5) -> activates -> opens the form
sgr_click( $pty, 20, 5 );
sgr_click( $pty, 20, 5 );
$pty->pump(1.3);
like( $pty->screen, qr/MOUSEFORM|Clicked open/,
    'double-clicking a menu item runs its action (opens the form)' );

# the process is still healthy (not crashed by the mouse handling)
$pty->send("\033");
$pty->pump(0.3);
$pty->send("\033");
$pty->pump(0.3);
$pty->send("\033");
my ( undef, $sig ) = $pty->wait(3);
isnt( $sig, 11, 'no segfault handling mouse events' );
