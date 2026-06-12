#!/usr/bin/perl
#
# Runtime colour-theme switching (FEATURE-REQUESTS A2).
#
# A `theme = NAME` global pulls in $THEMEDIR/ccfe.conf.NAME as if appended to
# the config path; the runtime switcher (the `theme:` menu action) lets the user
# pick a theme from a pop-up, persists it to the user config via ccfe-build and
# applies it immediately by reloading (A1).  This drives the whole path: a theme
# file that defines a config variable, picked at runtime, must make that variable
# resolve in a run: action that did not resolve before -- proving the theme was
# included AND the reload applied it, with no restart.
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

# Isolate the user config/data dirs so the switcher writes into the sandbox
# (and ccfe reads it back), never the real ~/.config.
my $home = tempdir( CLEANUP => 1 );
$ENV{XDG_CONFIG_HOME} = "$home/config";
$ENV{XDG_DATA_HOME}   = "$home/data";

# Leave exactly one installed theme so the pop-up order is deterministic
# ("default" first, then our theme second).  The theme defines a config var.
my $themedir = "$prefix/share/ccfe/themes";
unlink glob "$themedir/ccfe.conf.*";
open( my $th, '>', "$themedir/ccfe.conf.testtheme" )
  or plan skip_all => "theme: $!";
print {$th} "variables {\n  THEMEMARK = THEMEPICKED\n}\n";
close($th);

my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/themetest.menu" ) or plan skip_all => "write: $!";
print {$fh} <<'MENU';
title { Theme test }
item {
  id     = PICK
  descr  = Pick a colour theme
  action = theme:
}
item {
  id     = SHOW
  descr  = Show the theme variable
  action = run:echo VAL-$THEMEMARK
}
MENU
close($fh);

plan tests => 3;

my $p = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'themetest' );
$p->pump(1.2);

# Before any theme: $THEMEMARK is not a CCFE variable, so the run: action does
# not resolve it (the shell expands the unset name to nothing).
$p->send("\eOB");    # down -> SHOW
$p->pump(0.4);
$p->send("\r");      # run
$p->pump(1.0);
unlike( $p->screen, qr/THEMEPICKED/,
    'before switching, the theme variable does not resolve' );
$p->send("\e");      # leave the output browser
$p->pump(0.5);

# Open the theme picker (PICK, item 0) and confirm our theme is listed.
$p->send("\eOA");    # up -> PICK
$p->pump(0.4);
$p->send("\r");      # theme: -> pop-up list
$p->pump(0.8);
like( $p->screen, qr/testtheme/,
    'the theme picker lists the installed theme' );

# Select it (default(0) -> testtheme(1)), then dismiss the confirmation pop-up.
$p->send("\eOB");    # down -> testtheme
$p->pump(0.4);
$p->send("\r");      # select -> write pref + reload
$p->pump(1.0);
$p->send(" ");       # dismiss "theme saved" pop-up
$p->pump(0.6);

# After switching: the same run: action now resolves the theme's variable.
$p->send("\eOB");    # down -> SHOW
$p->pump(0.4);
$p->send("\r");
$p->pump(1.0);
like( $p->screen, qr/VAL-THEMEPICKED/,
    'after switching, the theme variable resolves (applied without restart)' );

$p->send("\e");
$p->pump(0.2);
$p->send("\e");
$p->pump(0.2);
$p->send("\e");
$p->pump(0.2);
