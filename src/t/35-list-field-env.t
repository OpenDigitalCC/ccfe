#!/usr/bin/perl
#
# A command: list_cmd can read another field's value via $CCFE_FIELD_<ID>.
#
# form_value_list now exports every field value as $CCFE_FIELD_<ID> before
# running a list_cmd (the same safe channel prepare_action gives action
# commands), so a F2 value list can depend on a value typed in another field
# without interpolating %{ID} into the shell string. The builder's "edit item"
# form relies on this (its item-id list depends on the menu-name field).
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

my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/fieldenv.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Field env test }
field {
  id    = SEED
  len   = 10
  type  = STRING
  label = Seed
}
field {
  id       = PICK
  len      = 24
  type     = STRING
  htab     = 1
  list_cmd = command:single-val:echo "picked-$CCFE_FIELD_SEED"
  label    = Pick (F2)
}
action { run:echo done }
FORM
close($fh);

plan tests => 1;

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'fieldenv' );
$pty->pump(1.3);
$pty->send("zaphod");    # type into the SEED field
$pty->pump(0.4);
$pty->send("\eOB");      # next field -> PICK
$pty->pump(0.4);
$pty->send("\eOQ");      # F2 = list: runs `echo "picked-$CCFE_FIELD_SEED"`
$pty->pump(0.8);
like( $pty->screen, qr/picked-zaphod/,
    'a list_cmd reads another field via $CCFE_FIELD_<ID>' );

$pty->send("\e");
$pty->pump(0.2);
$pty->send("\e");
$pty->pump(0.2);
$pty->send("\e");
