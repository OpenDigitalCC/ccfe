#!/usr/bin/perl
#
# Menu/form ownership management (FEATURE-REQUESTS C1).
#
# ccfe-build gains list-objects / list-users / list-groups and a `chown`
# command that changes ownership of one of the user's own objects (only under
# the user objdir -- a system object, locked by restricted mode, is never
# reachable).  Driven directly at the ccfe-build layer: enumerate, chown to
# self (always allowed), and the clean-failure paths (invalid name / missing
# object).  Also parse-checks the chown builder form.
#
use strict;
use warnings;
use FindBin qw($Bin);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Test::More;

my $src   = "$Bin/..";
my $build = "$src/tools/ccfe-build";
plan skip_all => 'no ccfe-build' unless -f $build;
plan skip_all => 'no installer'  unless -f "$src/install.sh";

# Parse-check the chown builder form (and the rest) via `ccfe -k`.
my $prefix = tempdir( CLEANUP => 1 );
my $log    = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
plan skip_all => "install failed: $log" unless $? == 0 && -x "$prefix/bin/ccfe";

plan tests => 6;

system("$prefix/bin/ccfe -k builder.d/chown >/dev/null 2>&1");
is( $? >> 8, 0, 'the chown builder form parses' );

# Isolated user objdir with one object.
my $home = tempdir( CLEANUP => 1 );
local $ENV{XDG_DATA_HOME}   = "$home/data";
local $ENV{XDG_CONFIG_HOME} = "$home/config";
my $objdir = "$home/data/ccfe/ccfe";
make_path($objdir);
open( my $o, '>', "$objdir/myobj.menu" ) or die "obj: $!";
print {$o} "title {\n  X\n}\n";
close($o);

my $me = getpwuid($<);

like( scalar(`sh "$build" list-objects 2>&1`), qr/^myobj$/m,
    'list-objects lists my object' );
like( scalar(`sh "$build" list-users 2>&1`), qr/\Q$me\E/,
    'list-users includes me' );

system(qq{sh "$build" chown myobj "$me" >/dev/null 2>&1});
is( $? >> 8, 0, 'chown to myself succeeds' );

system(qq{sh "$build" chown 'bad/name' "$me" >/dev/null 2>&1});
isnt( $? >> 8, 0, 'an invalid object name is refused' );

system(qq{sh "$build" chown nosuchobject "$me" >/dev/null 2>&1});
isnt( $? >> 8, 0, 'a missing object is refused' );
