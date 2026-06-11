#!/usr/bin/perl
#
# RESTRICTED shell-free execution (TD-1c).
#
# Under `restricted = yes`, system:/exec: are run via argv (system { $prog }
# @argv), not /bin/sh -c, so the allowlisted program name is what actually
# runs: shell chaining (`;`/`&&`/`$()`/backticks) and %{field} metacharacters
# can no longer reach a shell. This drives an allowlisted `echo` whose argument
# string contains `; touch <marker>` and asserts the chained touch never runs
# (the marker file is not created) while echo itself does.
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

# System config: restricted, allowing only `echo`.
open( my $cf, '>', "$prefix/etc/ccfe.conf" ) or plan skip_all => "conf: $!";
print {$cf} "global {\n  restricted = yes\n  restricted_allow = echo\n}\n";
close($cf);

# A menu whose item chains a touch onto an allowlisted echo.
my $marker = "$prefix/PWNED";
my $objs   = "$prefix/share/ccfe/objects/ccfe";
open( my $mf, '>', "$objs/rtest.menu" ) or plan skip_all => "menu: $!";
print {$mf} <<"MENU";
title { Restricted exec test }
item {
  id     = T
  descr  = run it
  action = system(wait_key): echo SYSMARKER; touch $marker
}
MENU
close($mf);

# TD-1b refuses user-writable object dirs under RESTRICTED, so a real kiosk
# keeps its objects system-owned and read-only.  Mirror that here: drop the
# owner-write bit so the dir is not -w and stays on the search path.
chmod 0555, $objs;

plan tests => 3;

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'rtest' );
$pty->pump(1.2);
like( $pty->screen, qr/run it/, 'the restricted menu opens' );

$pty->send("\r");    # activate the item -> system: action (wait_key)
$pty->pump(1.2);
like( $pty->screen, qr/SYSMARKER/,
    'the allowlisted echo runs (its argument string is printed verbatim)' );

ok( !-e $marker,
    'the chained `; touch` did NOT execute -- no shell (shell-free exec)' );

$pty->send(" ");     # dismiss the wait-for-key
$pty->pump(0.3);
$pty->send("\e");    # leave the menu

chmod 0755, $objs;    # restore so File::Temp can clean the tempdir up
