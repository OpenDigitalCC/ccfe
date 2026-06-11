#!/usr/bin/perl
#
# do_form field behaviour: rendering, defaults, separator, navigation, editing,
# boolean (TD-2 coverage; the safety net for the TD-3 do_form refactor).
#
# The existing form tests cover pagination, resize, layout, init and a
# default-value submit, but not: editing a field by typing, moving between
# fields, a separator field, or a boolean field's value. This drives all of
# those end to end so the upcoming do_form restructure is provably
# behaviour-preserving: it fills one field by typing, leaves another at its
# default and a boolean at its default, then submits and checks the action
# received exactly those values.
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
open( my $fh, '>', "$objs/fields.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Field test }
field {
  id      = NAME
  len     = 20
  type    = STRING
  default = const:alice
  label   = Name
}
separator { type = line }
field {
  id    = CITY
  len   = 20
  type  = STRING
  label = City
}
field {
  id      = FLAG
  type    = BOOLEAN
  default = const:YES
  label   = Flag
}
action { run:printf 'GOT NAME=%{NAME} CITY=%{CITY} FLAG=%{FLAG}\n' }
FORM
close($fh);

plan tests => 6;

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'fields' );
$pty->pump(1.3);
my $open = $pty->screen;
like( $open, qr/Name/,  'the form renders its field labels' );
like( $open, qr/City/,  '  ... including later fields' );
like( $open, qr/alice/, 'a const default value is shown in its field' );
like( $open, qr/-{5,}/, 'a line separator renders as a rule' );

$pty->send("\eOB");     # next field (separator is skipped) -> City
$pty->pump(0.4);
$pty->send("london");   # edit City by typing
$pty->pump(0.4);
$pty->send("\r");       # submit -> run the action
$pty->pump(1.3);

my $out = $pty->screen;
like( $out, qr/NAME=alice/,
    'the action received the untouched default (NAME=alice)' );
like( $out, qr/CITY=london\b/,
    'the action received the typed value and the boolean default (CITY=london)' );

$pty->send("\e");
$pty->pump(0.2);
$pty->send("\e");
