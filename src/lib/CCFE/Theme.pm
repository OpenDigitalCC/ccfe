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

# --- arbitrary foreground/background pairs --------------------------------
#
# The standard pairs (1..7) colour the foreground over the terminal's default
# background.  A full theme also wants background colours (a "white on blue"
# panel look), which needs a pair carrying both colours.  Those pairs are
# allocated lazily by pair_for(), numbered after the standard set.
#
# Ordering: a theme's *_attr strings are evaluated when the config is read,
# which is BEFORE start_color().  So pair_for() only assigns and remembers a
# pair NUMBER (no Curses call) -- exactly as COLOR_PAIR(6) is just bits until
# the pair is created -- and init_dynamic_pairs() actually creates them once
# colour is up.  A number is stable for a given (fg,bg) within a run.

my $DYN_BASE  = scalar(@PAIR_ORDER) + 1;    # first dynamic pair number (8)
my $next_pair = $DYN_BASE;
my %pair_cache;    # "fg:bg" (numbers) -> pair number
my @pair_defs;     # [ pairnum, fg, bg ] to create later

# Pair number for a (fg, bg) colour-name combo.  $bg defaults to the terminal
# default.  Allocates (and remembers for init_dynamic_pairs) a fresh number on
# first request for a combo; returns 0 (the default pair) for an unknown colour
# so a typo degrades to plain text rather than dying.
sub pair_for ( $fg, $bg = undef ) {
    my $f = color_number($fg);
    my $b = color_number($bg);
    return 0 unless defined $f and defined $b;
    my $key = "$f:$b";
    return $pair_cache{$key} if exists $pair_cache{$key};
    my $n = $next_pair++;
    $pair_cache{$key} = $n;
    push @pair_defs, [ $n, $f, $b ];
    return $n;
}

# Effectful: create every pair pair_for() handed out.  Call after
# start_color()/use_default_colors() (and after init_standard_pairs()).
# Skips any pair beyond the terminal's COLOR_PAIRS capacity.  Returns the
# number created.
sub init_dynamic_pairs () {
    my $max     = eval { Curses::COLOR_PAIRS() } || 0;
    my $created = 0;
    for my $d (@pair_defs) {
        next if $max and $d->[0] >= $max;
        Curses::init_pair(@$d);
        $created++;
    }
    return $created;
}

# Test/introspection helper: the (fg,bg) pairs allocated so far, as
# [pairnum, fg, bg] triples.
sub dynamic_pairs () { return @pair_defs }

1;

__END__

=head1 NAME

CCFE::Theme - optional colour support for CCFE

=head1 SYNOPSIS

    use CCFE::Theme;
    CCFE::Theme::init_standard_pairs();        # after start_color()
    my $n   = CCFE::Theme::pair_number('red');  # COLOR_PAIR index
    my $pid = CCFE::Theme::pair_for('red', 'blue');

=head1 DESCRIPTION

CCFE has always been monochrome (it draws with attribute constants only -
C<A_NORMAL> / C<A_REVERSE> / C<A_BOLD>). This module adds optional colour
without disturbing that: it pre-creates a conventional set of foreground colour
pairs over the terminal's default background, which the existing C<*_attr>
configuration can then reference as C<COLOR_PAIR(n)> (e.g.
C<stderr_attr = COLOR_PAIR(1) | A_BOLD> for bold red). When the terminal has no
colour, or C<NO_COLOR> is set, or the SIMPLE layout is in use, none of this runs
and the appearance is exactly as before.

The name/number maps are pure and unit-tested; the C<init_*> functions are the
effectful ones (they call C<Curses::init_pair>) and must run after
C<start_color()>/C<use_default_colors()>.

=head1 FUNCTIONS

=head2 palette

    my %name_to_color = CCFE::Theme::palette();

The colour-name to C<Curses::COLOR_*> constant map.

=head2 color_number

    my $c = CCFE::Theme::color_number($name);

The C<COLOR_*> number for a colour name (undef if unknown).

=head2 pair_number

    my $n = CCFE::Theme::pair_number($name);

The 1-based standard pair index for a foreground colour name - the C<n> to use
in C<COLOR_PAIR(n)>. Pair 1 = red, 2 = green, ... matching the ANSI foreground
order.

=head2 pair_names

    my @names = CCFE::Theme::pair_names();

The standard pair colour names, in index order.

=head2 init_standard_pairs

    CCFE::Theme::init_standard_pairs();

Allocate the conventional foreground-over-default-background pairs via
C<Curses::init_pair>. Effectful; call once after colour start-up.

=head2 pair_for

    my $pair = CCFE::Theme::pair_for($fg, $bg);

Resolve (allocating on demand) a colour pair for an arbitrary foreground/
background name combination, as used by the C<color_pair('fg','bg')> config
form. C<$bg> defaults to the terminal default.

=head2 init_dynamic_pairs / dynamic_pairs

Allocate, and report, the pairs created on demand by C<pair_for> beyond the
standard set.

=head1 SEE ALSO

L<ccfe.conf(5)>, L<curs_color(3X)>, F<REFACTOR.md> section 5.

=cut
