#!/usr/bin/perl
#
# The `-k NAME` parse-check CLI (the plugin linter).
#
# `ccfe -k NAME` validates a menu/form with the headless parser and exits
# without starting the terminal -- so this needs no pty, only a built ccfe.
# Exit codes: 0 = parses, 1 = parse error, 2 = not found.
#
use strict;
use warnings;
use FindBin qw($Bin);
use File::Temp qw(tempdir);
use Test::More;

my $src = "$Bin/..";

plan skip_all => 'Curses (libcurses-perl) not installed'
  unless eval { require Curses; 1 };
plan skip_all => "no installer at $src/install.sh" unless -f "$src/install.sh";

my $prefix = tempdir( CLEANUP => 1 );
my $bin    = "$prefix/bin/ccfe";
my $log    = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
plan skip_all => "install.sh failed: $log" unless $? == 0 && -x $bin;

# Returns (stdout+stderr, exit_code).
sub check {
    my ($name) = @_;
    my $out = `"$bin" -k "$name" 2>&1`;
    return ( $out, $? >> 8 );
}

# valid menu
my ( $o, $rc ) = check('demo');
is( $rc, 0, 'valid menu: exit 0' );
like( $o, qr/^OK: menu "demo"/, '  reports OK with kind/name' );

# valid menu (plugin)
( $o, $rc ) = check('sysmon');
is( $rc, 0, 'plugin menu: exit 0' );
like( $o, qr/6 item/, '  reports item count' );

# valid form inside a .d directory
( $o, $rc ) = check('sysmon.d/sar');
is( $rc, 0, 'form in a .d dir: exit 0' );
like( $o, qr/^OK: form /, '  recognised as a form' );

# not found
( $o, $rc ) = check('does_not_exist_xyz');
is( $rc, 2, 'missing name: exit 2' );

# malformed menu (unbalanced braces -> no items)
my $broken = "$prefix/lib/ccfe/broken.menu";
open( my $fh, '>', $broken ) or die "write $broken: $!";
print {$fh} "title { Broken\nitem { id=X descr=Y action=run:ls\n";
close($fh);
( $o, $rc ) = check('broken');
is( $rc, 1, 'malformed menu: exit 1' );
like( $o, qr/^ERROR: menu "broken"/, '  reports a parse error' );

done_testing();
