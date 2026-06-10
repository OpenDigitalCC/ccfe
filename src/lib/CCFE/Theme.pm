package CCFE::Theme;

# CCFE colour support.
#
# CCFE has always been monochrome (it draws with attribute constants only --
# A_NORMAL / A_REVERSE / A_BOLD).  This module adds optional colour without
# disturbing that: it pre-creates a conventional set of foreground colour
# pairs over the terminal's default background, which the existing `*_attr`
# configuration can then reference as COLOR_PAIR(n) (e.g.
# `stderr_attr = COLOR_PAIR(1) | A_BOLD` for bold red).  When the terminal has
# no colour, or NO_COLOR is set, or the SIMPLE layout is in use, none of this
# runs and the appearance is exactly as before.
#
# The name<->number maps are pure and unit-tested; init_standard_pairs() is
# the one effectful function (it calls Curses::init_pair) and must run after
# start_color()/use_default_colors().
#
# See REFACTOR.md section 5.

use v5.36;
use Curses ();

our $VERSION = '1.60';

# Conventional pair order: pair 1 = red, 2 = green, ... matching the ANSI
# foreground sequence so COLOR_PAIR(1) is the obvious "red".
my @PAIR_ORDER = qw( red green yellow blue magenta cyan white );

# Colour name -> Curses COLOR_* constant.
sub palette () {
    return (
        black   => Curses::COLOR_BLACK(),
        red     => Curses::COLOR_RED(),
        green   => Curses::COLOR_GREEN(),
        yellow  => Curses::COLOR_YELLOW(),
        blue    => Curses::COLOR_BLUE(),
        magenta => Curses::COLOR_MAGENTA(),
        cyan    => Curses::COLOR_CYAN(),
        white   => Curses::COLOR_WHITE(),
    );
}

# A colour name (or '-' / 'default' / empty) -> Curses colour number.
# '-1' means "the terminal's own default" (needs use_default_colors()).
# Returns undef for an unknown name.
sub color_number ($name) {
    return -1
      if not defined $name
      or $name eq ''
      or $name eq '-'
      or lc $name eq 'default';
    my %p = palette();
    return $p{ lc $name };
}

# The pair number a colour name maps to (1-based), or undef if it is not one
# of the standard foreground pairs.
sub pair_number ($name) {
    return undef unless defined $name;
    my $lc = lc $name;
    for my $i ( 0 .. $#PAIR_ORDER ) {
        return $i + 1 if $lc eq $PAIR_ORDER[$i];
    }
    return undef;
}

# The ordered list of standard pair names (index 0 -> pair 1).
sub pair_names () { return @PAIR_ORDER }

# Effectful: create the standard foreground colour pairs over the default
# background.  Returns the number of pairs created.  Caller must already have
# called Curses::start_color() and Curses::use_default_colors().
sub init_standard_pairs () {
    my %p = palette();
    my $n = 0;
    for my $name (@PAIR_ORDER) {
        $n++;
        Curses::init_pair( $n, $p{$name}, -1 );
    }
    return $n;
}

1;
