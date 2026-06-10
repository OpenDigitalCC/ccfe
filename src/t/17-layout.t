#!/usr/bin/perl
#
# Unit tests for the pure CCFE::Layout form-geometry helpers (ROADMAP M7).
#
# The value-column geometry and the page-advance arithmetic (worked out in M6)
# were written out twice in ccfe.pl -- once in do_form's initial layout and
# again, byte for byte, in resize_form's reflow.  That maths is pure, so it now
# lives in CCFE::Layout and the two sites share it.  These drive the helpers
# directly with hand-computed expectations; t/10-resize.t and t/11-layout.t
# remain the on-screen integration check.
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

require_ok('CCFE::Layout') or BAIL_OUT('cannot load CCFE::Layout');

# ---- field_geometry: right-aligned value, short label (no wrap) ---------
my $g = CCFE::Layout::field_geometry(
    {
        cols    => 80, len         => 20, label_x   => 2, label_w => 10,
        rflags_size => 2, value_pos => -1, gap       => 4, auto    => 1,
    }
);
is( $g->{val_x},     57, 'wide screen: value right-aligned (80-20-1-2)' );
is( $g->{wrap_rows}, 0,  '  short label does not wrap' );
is( $g->{label_w},   10, '  label keeps its natural width' );
is( $g->{dots_x},    12, '  dots start after the label (label_x+lw)' );
is( $g->{lvald_x},   56, '  left value delimiter is val_x-1' );
is( $g->{rvald_x},   77, '  right value delimiter is val_x+len' );
is( $g->{rflags_x},  78, '  right flag column is cols-rflags' );

# ---- field_geometry: long label wraps onto its own lines ----------------
$g = CCFE::Layout::field_geometry(
    {
        cols    => 40, len         => 20, label_x   => 2, label_w => 70,
        rflags_size => 2, value_pos => -1, gap       => 4, auto    => 1,
    }
);
is( $g->{val_x},     17, 'narrow screen: value still right-aligned (40-20-1-2)' );
is( $g->{label_w},   35, '  wrapped label box is full width (cols-label_x-rflags-1)' );
is( $g->{wrap_rows}, 2,  '  70-col label over a 35-col box wraps to 2 rows' );
is( $g->{dots_x},    2,  '  wrapped: dots run from the label margin' );

# ---- field_geometry: value clamped to just past the label ---------------
$g = CCFE::Layout::field_geometry(
    {
        cols    => 30, len         => 25, label_x   => 2, label_w => 5,
        rflags_size => 2, value_pos => -1, gap       => 4, auto    => 1,
    }
);
is( $g->{val_x}, 3, 'value never sits left of label_x+1 (clamped up)' );

# ---- field_geometry: explicit value_pos, no auto-wrap -------------------
$g = CCFE::Layout::field_geometry(
    {
        cols    => 80, len         => 20, label_x   => 2, label_w => 10,
        rflags_size => 2, value_pos => 40, gap       => 4, auto    => 0,
    }
);
is( $g->{val_x},     40, 'explicit value_pos is honoured verbatim' );
is( $g->{wrap_rows}, 0,  '  no wrap when not auto' );

# ---- field_geometry: a long label does NOT wrap unless auto -------------
$g = CCFE::Layout::field_geometry(
    {
        cols    => 80, len         => 20, label_x   => 2, label_w => 60,
        rflags_size => 2, value_pos => -1, gap       => 4, auto    => 0,
    }
);
is( $g->{wrap_rows}, 0,  'auto=0 suppresses wrapping even for a long label' );
is( $g->{dots_x},    62, '  dots stay after the (unwrapped) label' );

# ---- page_advance: first field opens page 1 -----------------------------
my $p = CCFE::Layout::page_advance(
    { y => 0, vtab => 0, wrap_rows => 0, mwinr => 20 } );
is( $p->{y},          0, 'first field sits at row 0' );
is( $p->{vr},         0, '  value row is 0' );
ok( $p->{page_start}, '  and it starts a new page' );

# ---- page_advance: a field that fits stays on the page ------------------
$p = CCFE::Layout::page_advance(
    { y => 5, vtab => 0, wrap_rows => 0, mwinr => 20 } );
is( $p->{y}, 5, 'a fitting field keeps its row' );
ok( !$p->{page_start}, '  and does not start a page' );

# ---- page_advance: a block that would overflow breaks to a new page ------
$p = CCFE::Layout::page_advance(
    { y => 19, vtab => 0, wrap_rows => 2, mwinr => 20 } );
is( $p->{y}, 0, 'a 3-row block at row 19 of 20 breaks to a new page' );
ok( $p->{page_start}, '  new page started' );

# ---- page_advance: vtab pushes the field down ---------------------------
$p = CCFE::Layout::page_advance(
    { y => 3, vtab => 2, wrap_rows => 1, mwinr => 20 } );
is( $p->{y},  5, 'vtab adds leading rows (3+2)' );
is( $p->{vr}, 6, '  value row is y + wrap_rows' );

# ---- page_advance: y at/over the window height wraps to a new page -------
$p = CCFE::Layout::page_advance(
    { y => 20, vtab => 0, wrap_rows => 0, mwinr => 20 } );
is( $p->{y}, 0, 'y == mwinr forces a page break' );

done_testing();
