#!/usr/bin/perl
#
# Meta/Alt key bindings via the keymap engine (FEATURE-REQUESTS A3).
#
# A `keymap { }` section binds a function to one or more key specs, where a spec
# may be an F-key, a Meta chord (M-x), a Ctrl chord (^X) or a plain key.  Here
# the `list` function gets an "M-l" alternate alongside its F-key; pressing
# Alt+L (ESC + l) in a form must trigger the value-list pop-up, proving the
# ESC-disambiguation input layer (read_key) and the event->function translation
# work end to end.
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

# Give `list` a Meta alternate (keeps F2 too).
my $conf = "$prefix/etc/ccfe.conf";
open( my $cf, '>>', $conf ) or plan skip_all => "conf: $!";
print {$cf} "\nkeymap {\n  list = F2, M-l\n}\n";
close($cf);

my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/metatest.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Meta test }
field {
  id       = PICK
  label    = Pick
  len      = 24
  list_cmd = command:single-val:echo METALISTMARK
}
action { run:true }
FORM
close($fh);

plan tests => 2;

# --- Meta alternate: Alt+L opens the value list ---------------------------
my $p = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'metatest' );
$p->pump(1.2);
$p->send("\el");    # ESC + l = Alt+L -> list
$p->pump(1.0);
like( $p->screen, qr/METALISTMARK/,
    'Alt+L (a Meta keymap binding) opens the value-list pop-up' );
$p->send("\e");     # close the list
$p->pump(0.3);
$p->send("\e");     # leave the form
$p->pump(0.3);

# --- the original F-key still works ---------------------------------------
my $q = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'metatest' );
$q->pump(1.2);
$q->send("\eOQ");    # F2 -> list (still bound)
$q->pump(1.0);
like( $q->screen, qr/METALISTMARK/,
    '  the F-key binding still works alongside the Meta alternate' );
$q->send("\e");
$q->pump(0.3);
$q->send("\e");
$q->pump(0.3);
