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

plan tests => 10;

use constant SIGSEGV => 11;
# A libform error code (E_NOT_CONNECTED == -11) leaking to exit() shows up to
# the shell as status 245 (256 - 11).  The exit-status guard must prevent that.
use constant LEAKED_ERR_STATUS => 245;

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

# A long form re-paginates when the terminal grows (uses the new vertical
# space instead of leaving it blank).
my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/long.form" ) or die "write: $!";
print {$fh} "title { Long }\n";
print {$fh}
  "field {\n  id    = F$_\n  len   = 5\n  type  = STRING\n  label = Field $_\n}\n"
  for 1 .. 40;
print {$fh} "action { run:true }\n";
close($fh);
sub last_pages {    # the M of the latest "Pg:N/M"
    my @m = $_[0]->screen =~ m{Pg:\d+/(\d+)}g;
    return $m[-1] // 0;
}
{
    my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'long' );
    $pty->pump(1.3);
    my $pages_small = last_pages($pty);
    $pty->resize( 80, 46 );    # much taller
    $pty->pump(1.3);
    my $pages_big = last_pages($pty);
    $pty->send("\033");
    $pty->pump(0.3);
    $pty->send("\033");
    my ( undef, $s ) = $pty->wait(3);
    isnt( $s, SIGSEGV, 'long form survives a grow resize' );
    cmp_ok( $pages_big, '<', $pages_small,
        "  form re-paginates to fewer pages when taller ($pages_small -> $pages_big)"
    );
}

# Shrinking to a tiny terminal (below the 80x24 minimum) must not crash.
{
    my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'sysmon' );
    $pty->pump(1.2);
    $pty->resize( 40, 10 );
    $pty->pump(0.9);
    $pty->resize( 100, 30 );
    $pty->pump(0.9);
    $pty->send("\033");
    $pty->pump(0.3);
    $pty->send("\033");
    my ( undef, $s ) = $pty->wait(3);
    isnt( $s, SIGSEGV, 'shrinking below the minimum size does not crash' );
}

# Launch a form on a WIDE terminal, then shrink narrow.  This is the real bug:
# the value fields are right-aligned to the launch width, so once the terminal
# is narrower than the value column, post_form() fails with E_NO_ROOM (-6), the
# form is left unposted, and the next loop iteration crashes on a NULL current
# field (surfacing to the shell as the leaked status 245).  A launch at 80x24
# does NOT reproduce it -- the window has to start wider than it ends.  Whether
# the unposted form actually crashes is platform-dependent, so we assert the
# deterministic precondition instead: resize_form must never leave post_form
# failing.  It widens the rebuilt window to hold every field, so the -d trace
# shows "post_form => 0" at every size.
{
    my $pty = CCFE::Test::Pty->spawn( 120, 40, "$prefix/bin/ccfe", '-d',
        'long' );
    $pty->pump(1.2);
    $pty->resize( 88, 24 );    # narrower than the right-aligned value column
    $pty->pump(0.9);
    $pty->resize( 40, 10 );    # tiny
    $pty->pump(0.9);
    $pty->resize( 100, 30 );
    $pty->pump(0.9);
    $pty->send("\033");
    $pty->pump(0.3);
    $pty->send("\033");
    my ( $exit, $sig ) = $pty->wait(3);
    isnt( $sig, SIGSEGV,
        'wide-launch form shrunk narrow does not crash' );

    my $log = '';
    if ( open( my $lh, '<', "$prefix/log/$ENV{USER}.log" ) ) {
        local $/;
        $log = <$lh>;
        close($lh);
    }
    my @posts = $log =~ /resize_form: post_form => (-?\d+)/g;
    ok( scalar(@posts), '  resize_form ran (post_form traced)' );
    is( ( scalar grep { $_ != 0 } @posts ),
        0, '  post_form never fails (no E_NO_ROOM) after a narrow resize' );
}
