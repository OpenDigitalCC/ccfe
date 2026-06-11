#!/usr/bin/perl
#
# RESTRICTED is a real boundary: config-lock (TD-1a) + user-dir refusal (TD-1b).
#
# Strengthened `restricted = yes`:
#  - TD-1a: a system (non-user-writable) config that sets restricted=yes locks
#    it; a later user-writable config cannot turn it off.
#  - TD-1b: under restricted, object dirs the user can write are dropped from
#    the search path, so a user-authored `run:` (unconstrained) menu is not
#    loaded.
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Test::More;

my $src = "$Bin/..";

eval { require CCFE::Test::Pty; 1 } or plan skip_all => "pty helper: $@";
plan skip_all => 'no Linux pseudo-terminal' unless CCFE::Test::Pty->available;
plan skip_all => 'Curses not installed'     unless eval { require Curses; 1 };
plan skip_all => 'no installer' unless -f "$src/install.sh";
plan skip_all => 'running as root (write checks are meaningless)' if $> == 0;

my $prefix = tempdir( CLEANUP => 1 );
my $log    = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
plan skip_all => "install failed: $log" unless $? == 0 && -x "$prefix/bin/ccfe";

# System config: restricted, locked by being non-user-writable. (It is read
# first on the search path, so it sets the policy before any user config.)
open( my $sc, '>', "$prefix/etc/ccfe.conf" ) or plan skip_all => "sysconf: $!";
print {$sc} "global {\n  restricted = yes\n}\n";
close($sc);
chmod 0444, "$prefix/etc/ccfe.conf";

# A separate HOME holds the user's attempts to escape: a config turning
# restricted off, and a run: menu in the user object dir.
my $home = tempdir( CLEANUP => 1 );
local $ENV{HOME} = $home;
make_path("$home/.config/ccfe");
open( my $uc, '>', "$home/.config/ccfe/ccfe.conf" ) or plan skip_all => "uc: $!";
print {$uc} "global {\n  restricted = no\n}\n";    # should be ignored (locked)
close($uc);

make_path("$home/.local/share/ccfe/ccfe");
open( my $um, '>', "$home/.local/share/ccfe/ccfe/escape.menu" )
  or plan skip_all => "um: $!";
print {$um} "title { ESCAPE_HATCH }\nitem { id=X\n descr=pwn\n action=run:sh }\n";
close($um);

plan tests => 2;

# TD-1a: the user config's `restricted = no` is ignored, so the F7 shell-escape
# key stays disabled -- it is removed from the on-screen key bar.
my $p1 = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'demo' );
$p1->pump(1.3);
unlike( $p1->screen, qr/\bShell\b/,
    'a user config cannot turn restricted off (F7 shell key stays hidden)' );
$p1->send("\e");
$p1->pump(0.2);

# TD-1b: the user-authored escape.menu in the user-writable object dir is not
# loaded under restricted (the dir is dropped from the path).
my $p2 = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'escape' );
$p2->pump(1.3);
unlike( $p2->screen, qr/ESCAPE_HATCH/,
    'a user-dir run: menu is refused under restricted' );
$p2->send("\e");
