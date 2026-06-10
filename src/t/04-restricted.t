#!/usr/bin/perl
#
# Security: RESTRICTED mode and command-execution hardening.
#
# CCFE can be deployed as a constrained front-end (kiosk / restricted login):
# RESTRICTED mode must close the ways a menu user could break out -- the F7
# shell escape, the system:/exec: verbs, and the runnable-script save -- while
# leaving normal menu use working.  This test loads the program headlessly
# (CCFE_TESTING) and exercises the policy decisions directly, then pins the
# wiring at the source level the way t/02 does for the issue-#1 fix.
#
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);

my $src = "$Bin/..";

$ENV{CCFE_TESTING} = 1;
require "$src/ccfe.pl";
no warnings 'once';

# ---- restricted_denies_shell() -----------------------------------------
$main::RESTRICTED = 0;
ok( !main::restricted_denies_shell(),
    'shell escape is allowed when not restricted' );
$main::RESTRICTED = 1;
ok( main::restricted_denies_shell(),
    'shell escape is denied in RESTRICTED mode' );

# ---- restricted_denies_verb() ------------------------------------------
$main::RESTRICTED       = 0;
@main::RESTRICTED_ALLOW = ();
ok( !main::restricted_denies_verb( 'system', 'vi /etc/passwd' ),
    'system: allowed when not restricted' );

$main::RESTRICTED = 1;
ok( main::restricted_denies_verb( 'system', 'vi /etc/passwd' ),
    'system: denied in RESTRICTED mode with an empty allowlist' );
ok( main::restricted_denies_verb( 'exec', '/bin/sh' ),
    'exec: denied in RESTRICTED mode' );
ok( !main::restricted_denies_verb( 'run', 'df -h' ),
    'run: is never gated by the allowlist (output-only view)' );
ok( !main::restricted_denies_verb( 'menu', 'demo' ),
    'menu: is never gated' );

@main::RESTRICTED_ALLOW = ( 'top', 'df' );
ok( !main::restricted_denies_verb( 'system', 'df -h' ),
    'an allowlisted program is permitted' );
ok( main::restricted_denies_verb( 'system', 'vi' ),
    'a non-allowlisted program is denied' );
ok( !main::restricted_denies_verb( 'system', '/usr/bin/df -h' ),
    'the allowlist matches the basename of a full path' );

# ---- harden_child_env() ------------------------------------------------
$ENV{LD_PRELOAD} = '/tmp/evil.so';
$ENV{LD_LIBRARY_PATH} = '/tmp';
$ENV{BASH_ENV}   = '/tmp/evil';
$ENV{ENV}        = '/tmp/evil';
$ENV{CDPATH}     = '/tmp';
main::harden_child_env();
ok( !exists $ENV{LD_PRELOAD},      'LD_PRELOAD stripped from child env' );
ok( !exists $ENV{LD_LIBRARY_PATH}, 'LD_LIBRARY_PATH stripped from child env' );
ok( !exists $ENV{BASH_ENV},        'BASH_ENV stripped' );
ok( !exists $ENV{ENV},             'ENV stripped' );
ok( !exists $ENV{CDPATH},          'CDPATH stripped' );
is( $ENV{IFS}, " \t\n", 'IFS reset to a safe value' );

# ---- source-level wiring guards (cannot be reached via the subs) -------
sub slurp {
    my ($f) = @_;
    open( my $fh, '<', $f ) or die "open $f: $!";
    local $/;
    my $c = <$fh>;
    close($fh);
    return $c;
}
my $code = slurp("$src/ccfe.pl");

like( $code, qr/\bRESTRICTED\b/, 'RESTRICTED is a recognised config parameter' );
like(
    $code,
    qr/grep\s*\{\s*\$_\s*ne\s*'shell_escape'\s*\}\s*\@MSKeys/,
    'shell_escape is stripped from the menu key bar under RESTRICTED'
);
like(
    $code,
    qr/harden_child_env\(\)/,
    'harden_child_env() is invoked in the startup path'
);
like(
    $code,
    qr/push\s+\@save_types,.*?unless\s+\$RESTRICTED/s,
    'the runnable-script save option is omitted under RESTRICTED'
);
like(
    $code,
    qr/\$ENV\{"CCFE_FIELD_\$id"\}/,
    'field values are exported as CCFE_FIELD_* for injection-safe commands'
);
like(
    $code,
    qr/restricted_denies_verb\(\s*'system'/,
    'system: dispatch is guarded by the restricted policy'
);
like(
    $code,
    qr/restricted_denies_verb\(\s*'exec'/,
    'exec: dispatch is guarded by the restricted policy'
);

done_testing();
