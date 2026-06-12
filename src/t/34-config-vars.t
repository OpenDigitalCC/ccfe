#!/usr/bin/perl
#
# Static interpolating config variables (FEATURE-REQUESTS item 3).
#
# A `variables { }` config section defines NAME = value pairs that may reference
# each other ($NAME / ${NAME}); the references are resolved once at config load.
# In menu/form actions and list_cmd commands, $NAME is then substituted with the
# resolved value (only defined names; any other $... is left for the shell).
# This drives all three: a cross-referenced variable in a run: action, the
# pass-through of an undefined $VAR to the shell, and a variable in a list_cmd.
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

# Append a variables{} section with a cross-reference to the system config.
my $conf = "$prefix/etc/ccfe.conf";
open( my $cf, '>>', $conf ) or plan skip_all => "conf: $!";
print {$cf} "\nvariables {\n  BASE_DIR = /tmp\n"
  . "  MSG = captured from \${BASE_DIR}\n}\n";
close($cf);

my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/vars.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Vars test }
field {
  id       = PICK
  label    = Pick
  len      = 24
  list_cmd = command:single-val:echo $MSG
}
action { run:echo "$MSG ; home=$HOME" }
FORM
close($fh);

plan tests => 3;

# --- run: action: cross-referenced variable + shell pass-through ----------
my $p = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'vars' );
$p->pump(1.2);
$p->send("\r");    # submit -> run -> output browser
$p->pump(1.3);
my $out = $p->screen;
like( $out, qr{captured from /tmp},
    'a cross-referenced $\{VAR} resolves in a run: action' );
like( $out, qr{home=/\w},
    '  an undefined $VAR is left for the shell to expand ($HOME)' );
$p->send("\e");
$p->pump(0.2);
$p->send("\e");
$p->pump(0.2);

# --- list_cmd command: a variable resolves there too (exec_command) -------
my $f = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'vars' );
$f->pump(1.2);
$f->send("\eOQ");    # F2 = list
$f->pump(0.8);
like( $f->screen, qr{captured from /tmp},
    'a variable resolves in a list_cmd command' );
$f->send("\e");
$f->pump(0.2);
$f->send("\e");
$f->pump(0.2);
$f->send("\e");
