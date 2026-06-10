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
my $broken = "$prefix/share/ccfe/objects/ccfe/broken.menu";
open( my $fh, '>', $broken ) or die "write $broken: $!";
print {$fh} "title { Broken\nitem { id=X descr=Y action=run:ls\n";
close($fh);
( $o, $rc ) = check('broken');
is( $rc, 1, 'malformed menu: exit 1' );
like( $o, qr/^ERROR: menu "broken"/, '  reports a parse error' );

# ---- the --dump / -D machine-readable output ----------------------------
require JSON::PP;

# --dump NAME (long form) prints a parseable menu as JSON
my $mjson = `"$bin" --dump demo 2>/dev/null`;
is( $? >> 8, 0, '--dump menu: exit 0' );
my $m = eval { JSON::PP::decode_json($mjson) };
ok( $m && $m->{kind} eq 'menu', '  output is JSON with kind=menu' );
ok( ref $m->{items} eq 'ARRAY' && @{ $m->{items} },
    '  items are a non-empty array' );
ok( ( grep { defined $_->{id} && exists $_->{action} } @{ $m->{items} } ),
    '  each item carries id/descr/action' );

# -D NAME (short form) prints a form, with typed fields
my $fjson = `"$bin" -D sysmon.d/sar 2>/dev/null`;
is( $? >> 8, 0, '-D form: exit 0' );
my $f = eval { JSON::PP::decode_json($fjson) };
ok( $f && $f->{kind} eq 'form', '  output is JSON with kind=form' );
ok( ref $f->{fields} eq 'ARRAY', '  fields are an array' );
ok( ( grep { defined $_->{type} } @{ $f->{fields} } ),
    '  fields carry a type name' );

# a missing name dumps nothing and exits 2 (like -k)
`"$bin" --dump does_not_exist_xyz 2>/dev/null`;
is( $? >> 8, 2, '--dump missing name: exit 2' );

# ---- the --plugins manifest lister --------------------------------------
my $plug = `"$bin" --plugins 2>/dev/null`;
is( $? >> 8, 0, '--plugins: exit 0' );
like( $plug, qr/^sysmon\s+1\.0\b/m,
    '  lists the installed sysmon plugin with its version' );
like( $plug, qr/provides:.*\bsysmon\b/,
    '  shows what the plugin provides' );

done_testing();
