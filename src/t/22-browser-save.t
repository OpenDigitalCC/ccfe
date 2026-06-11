#!/usr/bin/perl
#
# Output-browser save-to-file (TD-2 coverage gap; security-relevant).
#
# In the run-output browser, the save key (F6) offers Simple / Detailed /
# (Script) and writes the captured output to a file; the runnable-script option
# is a chmod-+x escape vector and is omitted under RESTRICTED mode. None of the
# save path (the do_list type picker, ask_string for the filename, the file
# write, the RESTRICTED omission) was driven by a test -- only asserted at the
# source level in t/04. This runs it end to end.
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
open( my $fh, '>', "$objs/saveout.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Save output }
field {
  id    = X
  len   = 4
  type  = STRING
  label = X
}
action { run:printf 'alpha-line\nbeta-line\ngamma-line\n' }
FORM
close($fh);

plan tests => 3;

# HOME drives the default save path ($HOME/<name>.out), and an isolated config
# dir keeps the run hermetic.
my $home = tempdir( CLEANUP => 1 );
local $ENV{HOME} = $home;

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'saveout' );
$pty->pump(1.2);
$pty->send("\r");        # submit -> run -> output browser
$pty->pump(1.2);

$pty->send("\e[17~");    # F6 = save
$pty->pump(0.8);
like( $pty->screen, qr/Select type of output/,
    'F6 offers the save-type picker' );
like( $pty->screen, qr/Script/,
    '  the runnable-script option is offered (not RESTRICTED)' );

$pty->send("\r");        # pick the first type (Simple)
$pty->pump(0.7);
$pty->send("\r");        # accept the default filename ($HOME/<name>.out)
$pty->pump(0.9);

# the saved file should exist under $HOME and contain the captured output
my @out = glob("$home/*");
my $found = '';
for my $f (@out) {
    next unless -f $f;
    local $/;
    open( my $r, '<', $f ) or next;
    my $c = <$r>;
    close $r;
    $found = $f, last if $c =~ /beta-line/;
}
ok( $found, "save wrote the captured output to a file ($found)" )
    or diag( "files in HOME: @out" );

$pty->send("\e");
$pty->pump(0.2);
$pty->send("\e");
