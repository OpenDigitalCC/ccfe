package CCFE::Layout;

# Pure form-geometry helpers (ROADMAP M7, REFACTOR.md §3).
#
# The value-column geometry and the page-advance arithmetic were worked out in
# M6 (right-aligned "classic SMIT" value column that expands on a wide screen,
# with the label wrapping onto its own line(s) when a long label on a narrow
# terminal would otherwise collide with the value).  That maths was written
# out twice -- once when do_form() first lays the form out, and again, byte for
# byte, when resize_form() reflows it for a new $LINES/$COLS.  It is pure
# (numbers in, numbers out: no curses, no globals), so it lives here and the
# two call sites share it; the actual new_field()/move_field() calls and the
# tracing stay in ccfe.pl.
#
# All inputs/outputs are in screen columns/rows.

use v5.36;

our $VERSION = '2.1';

# field_geometry(\%in) -> \%out : the value column, the (possibly wrapped)
# label box and the four marker/delimiter columns for one logical field.
#
#   in:  cols         current screen width ($COLS)
#        len          the value field's width
#        label_x      the label's left column
#        label_w      the label's natural display width (disp_width($label))
#        rflags_size  the right flag margin ($FIELD_RMARGIN)
#        value_pos    configured value column, or -1 for "auto/right-align"
#        gap          min columns to keep between label and value before wrap
#        auto         true when the value auto-right-aligns (NORMAL layout and
#                     value_pos == -1) -- only then can the label wrap
#
#   out: val_x        the value field's left column
#        wrap_rows    label height-1 (0 = label shares the value's row)
#        label_w      the label box width (full width when wrapped)
#        dots_x       where the dot leader / label-on-value-row starts
#        lvald_x      left value-delimiter column
#        rvald_x      right value-delimiter column
#        rflags_x     right flag-marker column
sub field_geometry ($in) {
    my $cols    = $in->{cols};
    my $len     = $in->{len};
    my $label_x = $in->{label_x};
    my $lw      = $in->{label_w};
    my $rflags  = $in->{rflags_size};

    my $val_x = $in->{value_pos};
    if ( $val_x == -1 ) {
        $val_x = $cols - $len - 1 - $rflags;
        $val_x = $label_x + 1 if $val_x < $label_x + 1;
    }

    my $label_w   = $lw;
    my $wrap_rows = 0;
    if ( $in->{auto} and $label_x + $lw + $in->{gap} > $val_x ) {
        $label_w   = $cols - $label_x - $rflags - 1;
        $label_w   = 1 if $label_w < 1;
        $wrap_rows = int( ( $lw + $label_w - 1 ) / $label_w );
        $wrap_rows = 1 if $wrap_rows < 1;
    }

    return {
        val_x     => $val_x,
        wrap_rows => $wrap_rows,
        label_w   => $label_w,
        dots_x    => $wrap_rows ? $label_x : $label_x + $lw,
        lvald_x   => $val_x - 1,
        rvald_x   => $val_x + $len,
        rflags_x  => $cols - $rflags,
    };
}

# page_advance(\%in) -> \%out : place one field's block on the current page,
# breaking to a new page when the whole (label + value) block will not fit.
#
#   in:  y          the running top row
#        vtab       this field's extra leading rows
#        wrap_rows  from field_geometry (block is wrap_rows+1 rows, else 1)
#        mwinr      the form sub-window's row count
#
#   out: y           this field's top row (0 after a page break)
#        vr          the value/marker row (y + wrap_rows)
#        page_start  true when this field opens a new page (y == 0)
sub page_advance ($in) {
    my $mwinr     = $in->{mwinr};
    my $wrap_rows = $in->{wrap_rows};
    my $block_h   = $wrap_rows ? $wrap_rows + 1 : 1;

    my $y = $in->{y} + $in->{vtab};
    $y = 0 if $y >= $mwinr or ( $y > 0 and $y + $block_h > $mwinr );

    return {
        y          => $y,
        vr         => $y + $wrap_rows,
        page_start => ( $y == 0 ),
    };
}

1;
