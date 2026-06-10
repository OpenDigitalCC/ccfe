#!/usr/bin/perl
#
# Terminal resize reflow (ROADMAP M6).
#
# Before this, KEY_RESIZE only did refresh(curscr) -- repainting the old
# geometry, so the content did not reflow. do_menu now rebuilds its windows
# and menu at the new $LINES/$COLS, and do_form rebuilds its window and
# re-posts. This drives a menu and a form on a pseudo-terminal, grows the
# window, and checks each repaints at the new size without crashing.
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

plan tests => 4;

use constant SIGSEGV => 11;

# Open NAME, count occurrences of /$marker/ before and after growing the
# terminal from 80x24 to 120x40; return ($signal, $before, $after).
sub drive_resize {
    my ( $name, $marker ) = @_;
    my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", $name );
    $pty->pump(1.3);
    my $before = () = $pty->screen =~ /$marker/g;
    $pty->resize( 120, 40 );
    $pty->pump(1.2);
    my $after = () = $pty->screen =~ /$marker/g;
    $pty->send("\033");
    $pty->pump(0.3);
    $pty->send("\033");
    my ( undef, $sig ) = $pty->wait(3);
    return ( $sig, $before, $after );
}

# A menu rebuilds its whole geometry on resize.
my ( $sig, $b, $a ) = drive_resize( 'sysmon', 'System resources' );
isnt( $sig, SIGSEGV, 'menu survives a terminal resize' );
cmp_ok( $a, '>', $b, '  menu repaints after the resize' );

# A form rebuilds its window and re-posts on resize.
( $sig, $b, $a ) = drive_resize( 'demo.d/recursive', 'Form recursivity test' );
isnt( $sig, SIGSEGV, 'form survives a terminal resize' );
cmp_ok( $a, '>', $b, '  form repaints after the resize' );
