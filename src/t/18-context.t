#!/usr/bin/perl
#
# Unit tests for the CCFE::Context run-state container (ROADMAP M7, Phase 0).
#
# The container is introduced empty: de-globalisation moves one structure onto
# it per phase.  For now it just has to construct a fresh, independent hashref
# with a seeded cfg sub-hash, so the later phases (and load_config) can assume
# $ctx->{cfg} exists.
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

require_ok('CCFE::Context') or BAIL_OUT('cannot load CCFE::Context');

my $ctx = CCFE::Context::new();
is( ref $ctx, 'HASH', 'new() returns a plain hashref' );
is( ref $ctx->{cfg}, 'HASH', '  with a seeded cfg sub-hash' );
is_deeply( $ctx->{cfg}, {}, '  that starts empty' );

# Each call is independent -- a child/fresh context must not alias an earlier
# one (this is what will replace the `local %form/%menu` recursion state).
my $other = CCFE::Context::new();
$other->{cfg}{probe} = 1;
ok( !exists $ctx->{cfg}{probe}, 'separate calls return independent containers' );

done_testing();
