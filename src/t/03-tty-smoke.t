#!/usr/bin/perl
#
# End-to-end terminal smoke test -- the real regression guard for the
# "segfault on forms / on startup" crash (issue #1).
#
# THE BUG: new_menu()/new_form() in the Curses (libcurses-perl) binding store
# the caller's packed ITEM**/FIELD** array pointer WITHOUT copying it -- the
# array must stay valid for the whole life of the menu/form (this is how the
# underlying ncurses menu/form libraries work).  CCFE built the array with an
# inline `new_menu( pack 'L!*', @fset )`, so the packed string was a temporary
# that Perl freed/reused as soon as the statement finished.  ncurses was then
# left holding a dangling pointer.  With >= 3 items the freed buffer happened
# to survive long enough to limp along; with 1-2 items (the demo and ccfe
# install menus, and every short form) the memory was reused immediately and
# the first menu/form operation dereferenced freed memory -> SIGSEGV, before a
# single character was painted.  v1.60 keeps the packed buffer in a lexical
# that outlives the menu/form, which is the fix this test guards.
#
# The earlier t/02-issue1-regression.t guards the *source* of the empty-list
# variant by pattern; this test actually RUNS the program on a pseudo-terminal
# and asserts the menus and the recursive form paint and exit without dying on
# SIGSEGV.  It needs a Linux pty, the Curses module, and a POSIX sh to run the
# installer, so it skips (rather than fails) where those are unavailable.
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/lib";
use File::Temp qw(tempdir);
use Test::More;

use constant SIGSEGV => 11;

BEGIN {
    eval { require CCFE::Test::Pty; 1 }
      or plan skip_all => "pty helper unavailable: $@";
}

plan skip_all => 'no Linux pseudo-terminal here'
  unless CCFE::Test::Pty->available;
plan skip_all => 'Curses (libcurses-perl) not installed'
  unless eval { require Curses; 1 };

my $src = "$Bin/..";
plan skip_all => "no installer at $src/install.sh" unless -f "$src/install.sh";

# A real batch install into a throwaway prefix -- this also exercises
# install.sh and proves the program works as actually shipped (paths
# templated, plugin installed), not just as a loose script.
my $prefix = tempdir( CLEANUP => 1 );
my $bin    = "$prefix/bin/ccfe";

{
    # install.sh references its files relative to the source dir.
    my $log = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
    plan skip_all => "install.sh failed: $log" unless $? == 0 && -x $bin;
}

plan tests => 7;

# Spawn the program on an 80x24 pty, let it paint, then send exit keys.
# Returns ($screen, $exit_code, $signal).
sub run_screen {
    my ( $menu, @keys ) = @_;
    my $pty = CCFE::Test::Pty->spawn( 80, 24, $bin, $menu );
    $pty->pump(1.5);                 # initial paint
    for my $k (@keys) {
        $pty->send($k);
        $pty->pump(0.7);
    }
    # ESC = Back; from a top-level screen that quits the program.  Send a
    # couple so we unwind out of a form-inside-a-menu as well.
    $pty->send("\033");
    $pty->pump(0.4);
    $pty->send("\033");
    my ( $exit, $sig ) = $pty->wait(3);
    return ( $pty->screen, $exit, $sig );
}

# --- the demo menu (1 item) used to SIGSEGV on startup -------------------
{
    my ( $screen, undef, $sig ) = run_screen('demo');
    isnt( $sig, SIGSEGV, 'demo menu does not crash on startup (issue #1)' );
    like( $screen, qr/CCFE demo menu/, '  demo menu actually painted' );
}

# --- the default ccfe menu (Demo / Configure / Build / install-test) -----
{
    my ( $screen, undef, $sig ) = run_screen('ccfe');
    isnt( $sig, SIGSEGV, 'ccfe default menu does not crash' );
    like( $screen, qr/Configure CCFE/, '  ccfe menu painted' );
}

# --- the sample plugin menu (6 items) -- the path that always "worked" ---
{
    my ( $screen, undef, $sig ) = run_screen('sysmon');
    isnt( $sig, SIGSEGV, 'sysmon plugin menu does not crash' );
}

# --- opening a FORM: the literal "segfault on forms" of issue #1 ---------
# Enter on the demo menu's first item opens demo.d/recursive.form, which
# goes through new_form() (also a dangling-buffer site before v1.60).
{
    my ( $screen, undef, $sig ) = run_screen( 'demo', "\n" );
    isnt( $sig, SIGSEGV, 'opening a form does not crash (segfault on forms)' );
    like( $screen, qr/Form recursivity test/, '  recursive form painted' );
}
