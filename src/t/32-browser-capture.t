#!/usr/bin/perl
#
# Output-browser capture phase (TD-3 safety net before the run_browse capture
# extraction).
#
# run_browse spawns the action via open3 and multiplexes the child's stdout and
# stderr through IO::Select into the output pad, counting lines per stream,
# buffering a trailing partial line (no final newline) until EOF, and recording
# the child exit status. None of that was driven end to end. This pins the
# observable results: both streams appear in the browser; the status line
# reports the right per-stream line counts and exit status; and a final line
# with no newline is still captured.
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

# A form whose action emits two stdout lines and one stderr line, then exits 3.
open( my $fh, '>', "$objs/capture.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Capture test }
field {
  id    = X
  len   = 4
  type  = STRING
  label = X
}
action { run:printf 'out-one\nout-two\n'; printf 'err-one\n' >&2; exit 3 }
FORM
close($fh);

# A form whose action emits a final line with no trailing newline.
open( my $ph, '>', "$objs/partial.form" ) or plan skip_all => "write: $!";
print {$ph} <<'FORM';
title { Partial test }
field {
  id    = X
  len   = 4
  type  = STRING
  label = X
}
action { run:printf 'head-line\nno-newline-tail' }
FORM
close($ph);

plan tests => 6;

# --- mixed stdout/stderr, line counts, exit status ----------------------
my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'capture' );
$pty->pump(1.2);
$pty->send("\r");    # submit -> run -> output browser
$pty->pump(1.3);
my $scr = $pty->screen;

like( $scr, qr/out-one.*out-two/s, 'stdout lines are captured into the browser' );
like( $scr, qr/err-one/,           'stderr is captured too (multiplexed in)' );
like( $scr, qr/ES=3/,              'the child exit status is reported (ES=3)' );
like( $scr, qr/stdout:\s*2\b/,     '  stdout line count is 2' );
like( $scr, qr/stderr:\s*1\b/,     '  stderr line count is 1' );

$pty->send("\e");    # leave browser
$pty->pump(0.2);
$pty->send("\e");    # leave form
$pty->pump(0.2);

# --- a final line with no trailing newline is still captured ------------
my $pty2 = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'partial' );
$pty2->pump(1.2);
$pty2->send("\r");
$pty2->pump(1.3);
like( $pty2->screen, qr/no-newline-tail/,
    'a trailing partial line (no final newline) is flushed at EOF' );

$pty2->send("\e");
$pty2->pump(0.2);
$pty2->send("\e");
