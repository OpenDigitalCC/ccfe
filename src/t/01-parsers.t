#!/usr/bin/perl
#
# Parser / plugin-format conformance.
#
# ccfe.pl is loaded headlessly (CCFE_TESTING=1 stops it before the curses
# main loop, see the guard near getopts()), then its pure parser subs
# load_menu()/load_form() are run against the in-tree demo and sysmon
# plugin fixtures.  This pins down the .menu / .form / .item file formats
# and the dynamic-menu directory mechanism the plugin system depends on,
# so a future refactor can't silently change them.
#
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);

my $src    = "$Bin/..";
my $plugin = "$Bin/../ccfe-plugin-sysmon";

$ENV{CCFE_TESTING} = 1;
require "$src/ccfe.pl";

# Point the menu/form search path at the in-tree fixtures.
no warnings 'once';    # @main::mf_path is a package global inside ccfe.pl
@main::mf_path = ( $src, $plugin );

# load_menu now fills a caller-provided hashref (M7 Phase 2), not a global.
my %menu;

# ---- static menu file --------------------------------------------------
is( main::load_menu( 'ccfe', \%menu ), $main::ES_NO_ERR,
    'load static ccfe.menu' );
like( $menu{title}, qr/CCFE Installation Test/, '  title parsed' );
is( $menu{items}[0]{id}, 'TEST', '  first item id' );
is( $menu{items}[0]{action}, 'run:cat it_works.txt',
    '  first item run: action' );
is( $menu{items}[1]{action}, 'menu:demo', '  second item chains a menu' );

# ---- dynamic (directory) menu: definition + *.item ---------------------
is( main::load_menu( 'demo', \%menu ), $main::ES_NO_ERR,
    'load dynamic demo.menu/ directory' );
like( $menu{title}, qr/CCFE demo menu/, '  title from definition file' );
ok( ( grep { $_->{id} eq 'RECURSIVE' } @{ $menu{items} } ),
    '  .item file injected as a menu item' );

# ---- plugin menu -------------------------------------------------------
is( main::load_menu( 'sysmon', \%menu ), $main::ES_NO_ERR,
    'load plugin sysmon.menu' );
ok( scalar( @{ $menu{items} } ) >= 6, '  has >= 6 items' );
my %act = map { $_->{id} => $_->{action} } @{ $menu{items} };
is( $act{SAR}, 'form:sysmon.d/sar', '  SAR item -> form: action' );
is( $act{TOP}, 'system:top',        '  TOP item -> system: action' );

# ---- form files --------------------------------------------------------
# load_form now fills a caller-provided hashref (M7 Phase 3), not a global;
# the second arg is the dir scalar-ref (here a throwaway).
my %form;
my $dir_ref;
is( main::load_form( 'demo.d/recursive', \$dir_ref, \%form ), $main::ES_NO_ERR,
    'load demo.d/recursive.form' );
like( $form{title}, qr/Form recursivity test/, '  form title parsed' );
ok( ( grep { $_->{id} eq 'COUNTER' } @{ $form{fields} } ),
    '  COUNTER field parsed' );
like( $form{action}, qr/^form:demo\.d\/recursive/,
    '  recursive action references itself' );

is( main::load_form( 'sysmon.d/sar', \$dir_ref, \%form ), $main::ES_NO_ERR,
    'load plugin sysmon.d/sar.form' );
ok( scalar( @{ $form{fields} } ) >= 1, '  sar.form has fields' );

# ---- not-found handling ------------------------------------------------
is( main::load_menu( 'nope_does_not_exist', \%menu ), $main::ES_NOT_FOUND,
    'missing menu -> ES_NOT_FOUND' );
is( main::load_form( 'nope/does_not_exist', \$dir_ref, \%form ),
    $main::ES_NOT_FOUND, 'missing form -> ES_NOT_FOUND' );

done_testing();
