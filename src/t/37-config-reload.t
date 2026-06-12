#!/usr/bin/perl
#
# Runtime configuration reload (FEATURE-REQUESTS A1).
#
# A `reload:` menu action (and a bound `reload` key) re-reads the config files
# at runtime and re-applies what can change without rebuilding the terminal --
# here a `variables {}` value substituted into a run: action.  This drives the
# end-to-end loop: run a command that echoes a config variable, change the
# variable ON DISK while ccfe is running, trigger the reload action, and confirm
# the SAME command now echoes the new value -- proving load_config re-ran and
# the change took effect without a restart.
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

my $conf = "$prefix/etc/ccfe.conf";

# Define the variable's first value in the system config.
open( my $cf, '>>', $conf ) or plan skip_all => "conf: $!";
print {$cf} "\nvariables {\n  GREET = ALPHAONE\n}\n";
close($cf);

# A two-item menu: SHOW echoes the variable through a run: action (so
# expand_vars substitutes it at run time), RELOAD re-reads the config.
my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/reloadtest.menu" ) or plan skip_all => "write: $!";
print {$fh} <<'MENU';
title { Reload test }
item {
  id     = SHOW
  descr  = Show the GREET variable
  action = run:echo MARK-$GREET
}
item {
  id     = RELOAD
  descr  = Reload configuration
  action = reload:
}
MENU
close($fh);

plan tests => 2;

my $p = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'reloadtest' );
$p->pump(1.2);

# SHOW (first item) -> run -> output browser shows the first value.
$p->send("\r");
$p->pump(1.0);
like( $p->screen, qr/MARK-ALPHAONE/,
    'the run: action echoes the original variable value' );
$p->send("\e");    # leave the output browser, back to the menu
$p->pump(0.5);

# Change the variable on disk: a later assignment wins on the next read.
open( my $cf2, '>>', $conf ) or die "conf reopen: $!";
print {$cf2} "\nvariables {\n  GREET = BETATWO\n}\n";
close($cf2);

# RELOAD (second item): re-read the config, then dismiss the confirmation pop-up.
$p->send("\eOB");    # down -> RELOAD
$p->pump(0.4);
$p->send("\r");      # trigger reload:
$p->pump(0.8);
$p->send(" ");       # dismiss the "configuration reloaded" pop-up
$p->pump(0.5);

# SHOW again -> the SAME command now echoes the NEW value.
$p->send("\eOA");    # up -> SHOW
$p->pump(0.4);
$p->send("\r");
$p->pump(1.0);
like( $p->screen, qr/MARK-BETATWO/,
    'after reload the run: action echoes the new value (no restart)' );

$p->send("\e");
$p->pump(0.2);
$p->send("\e");
$p->pump(0.2);
