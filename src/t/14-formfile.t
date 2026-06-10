#!/usr/bin/perl
#
# Unit tests for the pure CCFE::FormFile parser (ROADMAP M7).
#
# The .form bracket parser was lifted out of load_form() into a pure,
# terminal-free module so it can be exercised directly -- no install, no pty,
# no globals.  These drive parse($text, \%opt) and check the returned data
# structure, status and warnings.  The caller (load_form) owns the effectful
# rest: command/boolean defaults, the $COLS-dependent separator formatting and
# select-item resolution -- none of that lives here.
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

require_ok('CCFE::FormFile') or BAIL_OUT('cannot load CCFE::FormFile');

# The lookup maps/constants the caller injects.  Sentinel values are fine --
# the parser is map-driven and never interprets them.
my $SEPARATOR = 256;
my %opt       = (
    bool => { yes => 1, no => 0, true => 1, false => 0 },
    type => { string => 1, integer => 2, boolean => 8 },
    sep_type =>
      { text => 1, text_center => 2, line => 3, line_double => 4 },
    separator => $SEPARATOR,
    no        => 0,
);

# ---- a well-formed form -------------------------------------------------
my ( $f, $st, $w, $fc ) = CCFE::FormFile::parse( <<'EOT', \%opt );
title { My form }
top { line one
line two }
field {
  id      = NAME
  label   = Name
  len     = 30
  type    = string
  enabled = yes
}
separator {
  type = line
}
field {
  id      = AGE
  label   = Age
  type    = integer
}
bottom { footer }
init { setup }
action { run:save }
EOT

is( $st, 'ok', 'a well-formed form parses with status ok' );
is( $fc, 3,    '  three field blocks counted (two fields + a separator)' );
is( $f->{title},  'My form', '  title captured' );
is( $f->{init},   'setup',   '  init captured' );
is( $f->{action}, 'run:save', '  action captured' );
is_deeply( $f->{top}, [ 'line one', 'line two' ],
    '  top split into its lines' );
is_deeply( $f->{bottom}, ['footer'], '  bottom captured' );
is( scalar @{ $f->{fields} }, 3,        '  three fields' );
is( $f->{fields}[0]{id},      'NAME',   '  field 0 id' );
is( $f->{fields}[0]{label},   'Name',   '  field 0 label' );
is( $f->{fields}[0]{len},     '30',     '  field 0 len (verbatim string)' );
is( $f->{fields}[0]{type},    1,        '  field 0 type mapped via opt' );
is( $f->{fields}[0]{enabled}, 1,        '  field 0 enabled mapped to bool' );
is( $f->{fields}[2]{type},    2,        '  field 2 type (integer) mapped' );
is_deeply( $w, [], '  no warnings' );

# ---- separator: defaults applied, label left raw for the caller ---------
my $sep = $f->{fields}[1];
is( $sep->{type},     $SEPARATOR, 'separator: type set to the separator const' );
is( $sep->{len},      1,          '  separator len defaulted to 1' );
is( $sep->{enabled},  0,          '  separator enabled defaulted to false' );
is( $sep->{sep_type}, 3,          '  separator sub-type (line) carried through' );
is( $sep->{id}, 'CCFEFSEP001', '  separator got an auto id' );
ok( !defined( $sep->{label} ) || $sep->{label} !~ /-{2,}/,
    '  separator label NOT rule-formatted (deferred to caller)' );

# ---- an explicit separator id is kept, text carried raw -----------------
( $f, $st, $w, $fc ) = CCFE::FormFile::parse( <<'EOT', \%opt );
separator {
  id   = MYSEP
  type = text_center
  text = Hello
}
EOT
is( $f->{fields}[0]{id},       'MYSEP', 'explicit separator id is kept' );
is( $f->{fields}[0]{label},    'Hello', '  separator text stored raw as label' );
is( $f->{fields}[0]{sep_type}, 2,       '  text_center sub-type carried' );

# ---- duplicate field id warns but still parses --------------------------
( $f, $st, $w, $fc ) = CCFE::FormFile::parse(
    "field { id = X\nlabel = a }\nfield { id = X\nlabel = b }\n", \%opt );
is( $fc, 2, 'duplicate id: both fields kept' );
like( "@{$w}", qr/duplicated field ID "X"/, '  duplicate id is warned' );

# ---- a bad boolean value is a syntax error ------------------------------
( $f, $st, $w, $fc ) =
  CCFE::FormFile::parse( "field {\n id = A\n enabled = maybe\n}\n", \%opt );
is( $st, 'syntax_error', 'bad boolean value -> syntax_error' );
like( "@{$w}", qr/wrong value "maybe" for "enabled"/, '  and is warned' );

# ---- an unknown field type is a syntax error ----------------------------
( $f, $st, $w, $fc ) =
  CCFE::FormFile::parse( "field {\n id = A\n type = wibble\n}\n", \%opt );
is( $st, 'syntax_error', 'unknown field type -> syntax_error' );
like( "@{$w}", qr/unknown field type "wibble"/, '  and is warned' );

# ---- an unknown field attribute is a syntax error -----------------------
( $f, $st, $w, $fc ) =
  CCFE::FormFile::parse( "field {\n id = A\n bogus = 1\n}\n", \%opt );
is( $st, 'syntax_error', 'unknown field attribute -> syntax_error' );
like( "@{$w}", qr/unknown field attribute "bogus"/, '  and is warned' );

# ---- list_sep must be a quoted separator char ---------------------------
( $f, $st, $w, $fc ) =
  CCFE::FormFile::parse( qq(field {\n id = A\n list_sep = ","\n}\n), \%opt );
is( $st, 'ok', 'a quoted list_sep parses' );
is( $f->{fields}[0]{list_sep}, ',', '  list_sep char extracted' );

( $f, $st, $w, $fc ) =
  CCFE::FormFile::parse( "field {\n id = A\n list_sep = x\n}\n", \%opt );
is( $st, 'syntax_error', 'an unquoted list_sep is a syntax error' );

# ---- an unknown top-level block is a syntax error -----------------------
( $f, $st, $w, $fc ) = CCFE::FormFile::parse( "weird { stuff }\n", \%opt );
is( $st, 'syntax_error', 'unknown top-level block -> syntax_error' );

# ---- empty input: no fields, defensive empty arrays ---------------------
( $f, $st, $w, $fc ) = CCFE::FormFile::parse( '', \%opt );
is( $fc, 0, 'empty input: zero fields' );
is_deeply( $f->{fields}, [], '  fields is an empty array (not undef)' );
is_deeply( $f->{top},    [], '  top is an empty array (not undef)' );

done_testing();
