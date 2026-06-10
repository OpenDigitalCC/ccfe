#!/usr/bin/perl
#
# Unit tests for the pure CCFE::Action parser (ROADMAP M7).
#
# An action string `VERB[(opt,opt,...)]:ARGS` was parsed by the same five-line
# split/regex duplicated in do_menu() and do_form().  That parse is now a pure
# module; the dispatch (running the verb, prompting for `confirm`, honouring
# `log`/`wait_key`) stays in ccfe.pl.  These drive parse($str) directly.
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

require_ok('CCFE::Action') or BAIL_OUT('cannot load CCFE::Action');

# ---- a plain verb:args --------------------------------------------------
my $a = CCFE::Action::parse('run:ls -l /tmp');
is( $a->{verb}, 'run',        'verb captured' );
is( $a->{args}, 'ls -l /tmp', '  args captured verbatim (incl. spaces)' );
is_deeply( $a->{opts}, [], '  no options' );

# ---- only the first colon splits verb from args -------------------------
$a = CCFE::Action::parse('run:ssh host:cmd');
is( $a->{verb}, 'run',          'first colon splits' );
is( $a->{args}, 'ssh host:cmd', '  later colons stay in args' );

# ---- the verb is lower-cased --------------------------------------------
$a = CCFE::Action::parse('MENU:sub');
is( $a->{verb}, 'menu', 'verb is lower-cased' );
is( $a->{args}, 'sub',  '  args kept as-is' );

# ---- options in parentheses ---------------------------------------------
$a = CCFE::Action::parse('system(confirm,wait_key):reboot');
is( $a->{verb}, 'system', 'verb with options' );
is_deeply( $a->{opts}, [ 'confirm', 'wait_key' ], '  options split in order' );
is( $a->{args}, 'reboot', '  args after the option list' );

# ---- a single option ----------------------------------------------------
$a = CCFE::Action::parse('run(log):make');
is_deeply( $a->{opts}, ['log'], 'a single option parses' );
is( $a->{verb}, 'run',  '  verb still captured' );
is( $a->{args}, 'make', '  args still captured' );

# ---- a verb with no args (no colon) -------------------------------------
$a = CCFE::Action::parse('back');
is( $a->{verb}, 'back',  'a bare verb parses' );
is( $a->{args}, undef,   '  args is undef when there is no colon' );
is_deeply( $a->{opts}, [], '  no options' );

# ---- leading whitespace on the head is trimmed --------------------------
$a = CCFE::Action::parse('  run:x');
is( $a->{verb}, 'run', 'leading whitespace before the verb is trimmed' );

# ---- a malformed head yields an undef verb (caller finds no match) -------
$a = CCFE::Action::parse('123bad:x');
is( $a->{verb}, undef, 'a head that is not word/word(opts) -> undef verb' );
is( $a->{args}, 'x',   '  args still returned' );
is_deeply( $a->{opts}, [], '  no options' );

# ---- empty / undef input is safe ----------------------------------------
$a = CCFE::Action::parse('');
is( $a->{verb}, undef, 'empty string -> undef verb' );
$a = CCFE::Action::parse(undef);
is( $a->{verb}, undef, 'undef input -> undef verb (no warning/crash)' );

done_testing();
