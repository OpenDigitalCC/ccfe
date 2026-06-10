#!/usr/bin/perl
#
# Unit tests for the pure CCFE::Config section tokenizer (ROADMAP M7).
#
# The top-level `SECTION { ... }` walk was lifted out of load_config() -- the
# third copy of the same extract_bracketed loop -- into a pure, terminal-free
# module.  load_config keeps the (effectful, scope-bound) per-section dispatch:
# the eval-based colour/attribute assignments, the term-specific matching and
# the global side effects all stay there.  These tests drive parse($text) and
# check the returned section list, ordering, status and body trimming.
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

require_ok('CCFE::Config') or BAIL_OUT('cannot load CCFE::Config');

# ---- several sections, in file order ------------------------------------
my ( $secs, $st, $w ) = CCFE::Config::parse( <<'EOT');
GLOBAL {
  SCREEN_LAYOUT = smit
  HIDE_CURSOR = yes
}
FORM_GLOBAL {
  SHOW_DOTS = no
}
EOT

is( $st, 'ok', 'a well-formed config parses with status ok' );
is( scalar @{$secs}, 2,        '  two sections' );
is( $secs->[0]{name}, 'GLOBAL', '  section 0 name' );
is( $secs->[1]{name}, 'FORM_GLOBAL', '  section 1 name (order preserved)' );
like( $secs->[0]{body}, qr/SCREEN_LAYOUT = smit/, '  section 0 body captured' );
like( $secs->[0]{body}, qr/HIDE_CURSOR = yes/,    '  section 0 second line' );
unlike( $secs->[0]{body}, qr/[{}]/, '  body has the braces trimmed off' );
like( $secs->[1]{body}, qr/^SHOW_DOTS = no$/, '  section 1 body trimmed' );
is_deeply( $w, [], '  no warnings' );

# ---- a repeated section is kept in order, applied by the caller ---------
( $secs, $st, $w ) = CCFE::Config::parse(
    "GLOBAL { PATH = a }\nGLOBAL { PATH = b }\n");
is( scalar @{$secs}, 2, 'a repeated section is kept (not merged)' );
like( $secs->[0]{body}, qr/PATH = a/, '  first occurrence' );
like( $secs->[1]{body}, qr/PATH = b/, '  second occurrence' );

# ---- a term-specific section keeps its dotted name verbatim -------------
( $secs, $st, $w ) =
  CCFE::Config::parse("FIELD_ATTR.xterm {\n  LABEL_FG = COLOR_RED\n}\n");
is( $secs->[0]{name}, 'FIELD_ATTR.xterm',
    'a dotted/term-specific section name is preserved verbatim (case kept)' );

# ---- an unterminated bracket walk is a syntax error ---------------------
( $secs, $st, $w ) = CCFE::Config::parse("GLOBAL { PATH = a\n");
is( $st, 'syntax_error', 'an unterminated section -> syntax_error' );

# ---- empty input: no sections (the !pos guard flags it, as the original
#      load_config did -- an empty/comment-only config is a syntax error) ----
( $secs, $st, $w ) = CCFE::Config::parse('');
is( $st, 'syntax_error', 'empty input trips the unterminated-walk guard' );
is_deeply( $secs, [], '  no sections (empty array, not undef)' );

done_testing();
