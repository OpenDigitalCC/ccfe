#!/usr/bin/perl
#
# Keymap preset switching at runtime (FEATURE-REQUESTS A3).
#
# The "safe" preset gives every function a Meta/Alt alternate.  This drives the
# runtime switcher: with the default map, Alt+L does nothing; after selecting
# the "safe" preset from the keymap picker (which writes `keymap = safe` to the
# user config and reloads), Alt+L opens a form's value list -- proving the
# preset was included and applied without a restart.
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

# Isolate the user config so the switcher writes into the sandbox.
my $home = tempdir( CLEANUP => 1 );
$ENV{XDG_CONFIG_HOME} = "$home/config";
$ENV{XDG_DATA_HOME}   = "$home/data";

# Leave only the "safe" preset so the picker order is deterministic
# ("default" first, "safe" second).
my $kmdir = "$prefix/share/ccfe/keymaps";
for my $f ( glob "$kmdir/ccfe.keys.*" ) {
    unlink $f unless $f =~ /\.safe$/;
}
plan skip_all => 'safe preset missing' unless -f "$kmdir/ccfe.keys.safe";

my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $mf, '>', "$objs/kmtest.menu" ) or plan skip_all => "write: $!";
print {$mf} <<'MENU';
title { Keymap test }
item {
  id     = PICK
  descr  = Pick a key map
  action = keymap:
}
item {
  id     = FORM
  descr  = Open the list form
  action = form:listform
}
MENU
close($mf);

open( my $ff, '>', "$objs/listform.form" ) or plan skip_all => "write: $!";
print {$ff} <<'FORM';
title { List form }
field {
  id       = PICK
  label    = Pick
  len      = 24
  list_cmd = command:single-val:echo KMLISTMARK
}
action { run:true }
FORM
close($ff);

plan tests => 2;

my $p = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'kmtest' );
$p->pump(1.2);

# Before: open the form, Alt+L does nothing (no Meta binding in the default map).
$p->send("\eOB");    # down -> FORM
$p->pump(0.4);
$p->send("\r");      # open the form
$p->pump(0.8);
$p->send("\el");     # Alt+L -> (unbound)
$p->pump(0.7);
unlike( $p->screen, qr/KMLISTMARK/,
    'with the default map, Alt+L does not open the list' );
$p->send("\e");      # leave the form
$p->pump(0.5);

# Switch to the "safe" preset via the picker.
$p->send("\eOA");    # up -> PICK
$p->pump(0.4);
$p->send("\r");      # keymap: -> pop-up
$p->pump(0.8);
$p->send("\eOB");    # down -> safe
$p->pump(0.4);
$p->send("\r");      # select -> write pref + reload
$p->pump(1.0);
$p->send(" ");       # dismiss confirmation
$p->pump(0.6);

# After: open the form again; now Alt+L opens the value list.
$p->send("\eOB");    # down -> FORM
$p->pump(0.4);
$p->send("\r");
$p->pump(0.8);
$p->send("\el");     # Alt+L -> list (safe preset)
$p->pump(0.8);
like( $p->screen, qr/KMLISTMARK/,
    'after the "safe" preset, Alt+L opens the list (applied, no restart)' );

$p->send("\e");
$p->pump(0.2);
$p->send("\e");
$p->pump(0.2);
$p->send("\e");
$p->pump(0.2);
