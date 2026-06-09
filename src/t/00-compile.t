#!/usr/bin/perl
#
# ccfe.pl must compile cleanly.  This is the cheapest guard against an
# edit that breaks the (very large) single-file program.
#
use strict;
use warnings;
use Test::More tests => 1;
use FindBin qw($Bin);

my $script = "$Bin/../ccfe.pl";
my $out = qx{perl -c "$script" 2>&1};
like( $out, qr/syntax OK/, 'ccfe.pl compiles cleanly' )
  or diag($out);
