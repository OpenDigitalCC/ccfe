#!/usr/bin/perl
#
# Output-browser search (TD-2 coverage gap).
#
# A run: action streams its output into a curses pad (run_browse); `/` prompts
# for a pattern and jumps to the first match, `n` to the next. That search
# machinery (get_search_buff / search_all / search_next, plus the ask_string
# prompt) was never exercised by a test -- the other pty tests only open the
# browser and exit. This drives a 50-line output and asserts a match below the
# first screen scrolls into view, and that a non-match reports "Pattern not
# found".
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
plan skip_all => 'no seq(1)'    unless `sh -c 'command -v seq'`;

my $prefix = tempdir( CLEANUP => 1 );
my $log    = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
plan skip_all => "install failed: $log" unless $? == 0 && -x "$prefix/bin/ccfe";

# A form whose action emits 50 uniquely-marked lines (rowNN_end), so a target
# below the first screen exists to scroll to.
my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/longout.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Long output }
field {
  id    = X
  len   = 4
  type  = STRING
  label = X
}
action { run:seq -f 'row%g_end' 1 50 }
FORM
close($fh);

plan tests => 5;

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'longout' );
$pty->pump(1.2);
$pty->send("\r");    # submit -> run -> output browser
$pty->pump(1.3);

# The browser follows the streaming output, so it opens at the END.
like( $pty->screen, qr/row50_end/, 'browser opens at the end of the output' );
unlike( $pty->screen, qr/row1_end/,
    '  the top of the output is scrolled off' );

# `/` opens the find prompt; searching the off-screen top scrolls up to it.
$pty->send("/");
$pty->pump(0.6);
like( $pty->screen, qr/Enter Search Pattern/, 'the `/` find prompt appears' );
$pty->send("row1_end\r");
$pty->pump(0.9);
like( $pty->screen, qr/row1_end/,
    'search jumps to the match (get_search_buff/search_all/search_next)' );

# a non-existent pattern reports "Pattern not found".
$pty->send("/");
$pty->pump(0.5);
$pty->send("nomatch_zzz_qqq\r");
$pty->pump(0.7);
like( $pty->screen, qr/Pattern not found/, 'a miss reports "Pattern not found"' );

$pty->send("\e");    # dismiss the not-found message / leave the browser
$pty->pump(0.2);
$pty->send("\e");
$pty->pump(0.2);
$pty->send("\e");    # leave the form
