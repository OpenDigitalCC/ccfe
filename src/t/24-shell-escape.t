#!/usr/bin/perl
#
# F7 shell escape (TD-2 coverage gap).
#
# The F7 shell escape (call_shell) suspends curses, runs an interactive subshell
# in the raw terminal, and resumes the TUI on `exit`. Its RESTRICTED-mode
# *denial* is unit-tested (t/04/t/05), but the actual spawn-and-return was never
# driven. This opens the demo menu, drops to a shell, runs a marker command,
# and exits back -- asserting both that the shell ran and that the TUI is
# restored.
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

plan tests => 2;

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'demo' );
$pty->pump(1.2);

$pty->send("\e[18~");    # F7 = shell escape -> subshell in the raw terminal
$pty->pump(0.8);
$pty->send("echo SHELL_ESC_MARKER\r");
$pty->pump(0.8);
like( $pty->screen, qr/SHELL_ESC_MARKER/,
    'the F7 subshell runs a command' );

$pty->send("exit\r");    # leave the subshell -> curses resumes
$pty->pump(1.0);
like( $pty->screen, qr/CCFE demo menu|demo/,
    'the TUI is restored after the shell exits' );

$pty->send("\e");        # leave the menu
