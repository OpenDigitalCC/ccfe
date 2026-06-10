#!/usr/bin/perl
#
# Unit tests for CCFE::Restrict -- the pure security-policy module.
#
# These need no terminal and no ccfe.pl: the module is a functional core
# (every decision is a pure function of its arguments), which is the whole
# point of extracting it.  ccfe.pl's behavioural wiring is covered by
# t/04-restricted.t.
#
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";

use_ok('CCFE::Restrict') or BAIL_OUT('cannot load CCFE::Restrict');

# ---- denies_shell ------------------------------------------------------
ok( !CCFE::Restrict::denies_shell(0), 'shell allowed when not restricted' );
ok( CCFE::Restrict::denies_shell(1),  'shell denied when restricted' );

# ---- denies_verb -------------------------------------------------------
ok( !CCFE::Restrict::denies_verb( 0, [], 'system', 'vi' ),
    'system allowed when not restricted' );
ok( CCFE::Restrict::denies_verb( 1, [], 'system', 'vi' ),
    'system denied when restricted with empty allowlist' );
ok( CCFE::Restrict::denies_verb( 1, undef, 'exec', '/bin/sh' ),
    'exec denied when restricted (undef allowlist tolerated)' );
ok( !CCFE::Restrict::denies_verb( 1, [], 'run', 'df -h' ),
    'run is never gated' );
ok( !CCFE::Restrict::denies_verb( 1, [], 'menu', 'demo' ),
    'menu is never gated' );
ok( !CCFE::Restrict::denies_verb( 1, [ 'top', 'df' ], 'system', 'df -h' ),
    'allowlisted program permitted' );
ok( CCFE::Restrict::denies_verb( 1, ['top'], 'system', 'vi' ),
    'non-allowlisted program denied' );
ok(
    !CCFE::Restrict::denies_verb( 1, ['df'], 'system', '/usr/bin/df -h' ),
    'allowlist matches the basename of a full path'
);
ok( CCFE::Restrict::denies_verb( 1, ['df'], 'system', '' ),
    'empty command denied under restriction' );

# ---- harden_env --------------------------------------------------------
my %env = (
    LD_PRELOAD      => '/tmp/evil.so',
    LD_LIBRARY_PATH => '/tmp',
    BASH_ENV        => '/tmp/x',
    ENV             => '/tmp/x',
    CDPATH          => '/tmp',
    PATH            => '/usr/bin',
);
CCFE::Restrict::harden_env( \%env );
ok( !exists $env{LD_PRELOAD},      'LD_PRELOAD stripped' );
ok( !exists $env{LD_LIBRARY_PATH}, 'LD_LIBRARY_PATH stripped' );
ok( !exists $env{BASH_ENV},        'BASH_ENV stripped' );
ok( !exists $env{ENV},             'ENV stripped' );
ok( !exists $env{CDPATH},          'CDPATH stripped' );
is( $env{IFS},  " \t\n",   'IFS reset to a safe value' );
is( $env{PATH}, '/usr/bin', 'unrelated variables left intact' );

# ---- sh_quote ----------------------------------------------------------
is( CCFE::Restrict::sh_quote('plain'), "'plain'", 'plain value quoted' );
is( CCFE::Restrict::sh_quote(q{a'b}), q{'a'\''b'},
    'embedded single quote escaped' );
is( CCFE::Restrict::sh_quote('; rm -rf ~'), q{'; rm -rf ~'},
    'metacharacters neutralised into one literal word' );
is( CCFE::Restrict::sh_quote(undef), q{''}, 'undef becomes empty quoted word' );

done_testing();
