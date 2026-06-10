#!/usr/bin/perl
#
# Form submit -> action substitution + run (regression for M7 Phase 3).
#
# Submitting a form (Enter) runs its `action`, with each `%{FIELDID}` replaced
# by that field's current value.  That path fires do_form's nested helper
# closures -- sync_fields_val (read the field buffers) and prepare_action
# (substitute %{...} from the field values) -- which M7 Phase 3 turned from
# `local`-global-reading named subs into anonymous closures over do_form's
# per-call %form/@fp/$cform.  The other pty tests only open/navigate a form;
# this one submits it, so the submit-path closures actually run against the
# lexical state.
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

# A one-field form: the field defaults to "world"; the action echoes a marker
# built from that field's value via %{NAME} substitution.
my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/submit.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Submit test }
field {
  id      = NAME
  len     = 20
  type    = STRING
  default = const:world
  label   = Name
}
action { run:echo HELLO-%{NAME} }
FORM
close($fh);

plan tests => 2;

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'submit' );
$pty->pump(1.3);
like( $pty->screen, qr/world/, 'the field shows its default value' );

$pty->send("\r");        # Enter = submit the form / run the action
$pty->pump(1.5);
like( $pty->screen, qr/HELLO-world/,
    'submit runs the action with %{NAME} substituted (sync/prepare closures)' );

$pty->send("\e");        # leave the output browser
$pty->pump(0.3);
$pty->send("\e");        # leave the form
