#!/usr/bin/perl
#
# Guided builders (ROADMAP M5): the ccfe-build backend and the builder
# menus/forms that drive it.
#
# ccfe-build writes menus/forms/config into the user's XDG directories and
# validates objects with `ccfe -k`.  The builder forms pass field values as
# $CCFE_FIELD_* (injection-safe).  This tests the backend directly, parse-
# checks the shipped builder objects, and drives one builder form on a pty to
# prove the form -> $CCFE_FIELD_* -> ccfe-build -> file flow end to end.
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/lib";
use File::Temp qw(tempdir);
use Test::More;

my $src = "$Bin/..";
plan skip_all => 'Curses not installed' unless eval { require Curses; 1 };
plan skip_all => 'no installer' unless -f "$src/install.sh";

my $prefix = tempdir( CLEANUP => 1 );
my $log    = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
plan skip_all => "install failed: $log" unless $? == 0 && -x "$prefix/bin/ccfe";

my $bin   = "$prefix/bin";
my $build = "$bin/ccfe-build";
plan skip_all => 'ccfe-build not installed' unless -x $build;

my $data = tempdir( CLEANUP => 1 );
my $cfg  = tempdir( CLEANUP => 1 );

# Run ccfe-build with the builder environment; returns (output, exit).
sub build {
    local @ENV{qw(CCFE_BIN_DIR XDG_DATA_HOME XDG_CONFIG_HOME)} =
      ( $bin, $data, $cfg );
    my $cmd = join ' ', map { "'$_'" } ( $build, @_ );
    my $out = `$cmd 2>&1`;
    return ( $out, $? >> 8 );
}
my $objs = "$data/ccfe/ccfe";

# ---- backend: menu ------------------------------------------------------
my ( $o, $rc ) = build( 'new-menu', 'mymenu', 'My menu' );
is( $rc, 0, 'new-menu exits 0' );
ok( -f "$objs/mymenu.menu", '  menu file written to the XDG data dir' );

( $o, $rc ) = build( 'add-item', 'mymenu', 'DISK', 'Disk usage', 'run:df -h' );
is( $rc, 0, 'add-item exits 0' );
like( $o, qr/OK: menu "mymenu".*1 item/s, '  menu re-validated with the item' );

# ---- backend: form ------------------------------------------------------
( $o, $rc ) = build( 'new-form', 'myform', 'My form' );
is( $rc, 0, 'new-form exits 0' );
( $o, $rc ) = build( 'add-field', 'myform', 'NAME', 'Your name', 'STRING' );
is( $rc, 0, 'add-field exits 0' );
( $o, $rc ) = build( 'set-action', 'myform', 'run:echo hi' );
is( $rc, 0, 'set-action exits 0' );
like( $o, qr/OK: form "myform"/, '  form validates once it has an action' );

# ---- backend: config ----------------------------------------------------
( $o, $rc ) = build( 'set-config', 'restricted', 'yes' );
is( $rc, 0, 'set-config exits 0' );
my $conf = do { local ( @ARGV, $/ ) = "$cfg/ccfe/ccfe.conf"; <> };
like( $conf, qr/restricted\s*=\s*yes/, '  setting written to the user config' );

# ---- backend: validation / safety --------------------------------------
( $o, $rc ) = build( 'new-menu', 'bad name!', 'x' );
isnt( $rc, 0, 'an invalid object name is rejected' );

# ---- shipped builder objects parse -------------------------------------
for my $name (
    'builder', 'builder.d/newmenu', 'builder.d/additem',
    'builder.d/newform', 'builder.d/addfield', 'builder.d/finishform',
    'builder.d/settings'
  )
{
    my $out = `"$bin/ccfe" -k "$name" 2>&1`;
    is( $? >> 8, 0, "builder object '$name' parses" );
}

# ---- end-to-end: drive a builder form on a pty -------------------------
SKIP: {
    eval { require CCFE::Test::Pty; 1 } or skip( 'pty helper', 1 );
    skip( 'no pty', 1 ) unless CCFE::Test::Pty->available;
    local @ENV{qw(XDG_DATA_HOME XDG_CONFIG_HOME)} = ( $data, $cfg );
    my $pty =
      CCFE::Test::Pty->spawn( 80, 24, "$bin/ccfe", 'builder.d/newmenu' );
    $pty->pump(1.5);
    $pty->send('viapty');    # MENUNAME
    $pty->pump(0.5);
    $pty->send("\r");        # submit -> runs ccfe-build new-menu
    $pty->pump(1.5);
    $pty->send('q');
    $pty->pump(0.3);
    $pty->send("\033");
    $pty->pump(0.3);
    $pty->send("\033");
    $pty->wait(3);
    ok( -f "$objs/viapty.menu",
        'a builder form created a menu end-to-end (form -> CCFE_FIELD_* -> ccfe-build)'
    );
}

done_testing();
