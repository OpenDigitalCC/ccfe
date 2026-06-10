#!/usr/bin/perl
#
# Form init command -> field value population (regression for M7 Phase 1).
#
# A form's `init { command:... }` block runs a command whose `id=value` stdout
# lines pre-fill the form's fields.  Those values flow through do_form's
# per-form field-value map -- the `%field_vals` that M7 Phase 1 turned from a
# `local` global into an explicit per-call lexical threaded into
# load_persistent().  The existing pty tests only navigate a form of default
# (empty) fields, so this drives the populated path end to end: it asserts the
# init command's value actually renders in the field, which exercises the
# field_vals write (init parse) and read (field creation) sites Phase 1 changed.
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

# A one-field form whose init command pre-fills that field with a known marker.
my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $fh, '>', "$objs/initval.form" ) or plan skip_all => "write: $!";
print {$fh} <<'FORM';
title { Init value test }
field {
  id    = GREETING
  len   = 20
  type  = STRING
  label = Greeting
}
init { command:printf 'GREETING=hello-init\n' }
action { run:true }
FORM
close($fh);

plan tests => 2;

my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'initval' );
$pty->pump(1.3);
my $screen = $pty->screen;

like( $screen, qr/Greeting/, 'the form opens and shows the field label' );
like( $screen, qr/hello-init/,
    'the init command value is populated into the field (field_vals path)' );

$pty->send("\e");    # leave the form; DESTROY reaps the child
