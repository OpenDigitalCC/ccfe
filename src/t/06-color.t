#!/usr/bin/perl
#
# Colour support: the pure CCFE::Theme maps, plus an end-to-end check that a
# configured colour attribute actually produces coloured output.
#
# CCFE stays monochrome unless the terminal supports colour; colour is opt-in
# through the existing *_attr configuration (e.g. stdout_attr = COLOR_PAIR(2)),
# which works because CCFE pre-creates the standard foreground pairs.  See
# CCFE::Theme and REFACTOR.md section 5.
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use File::Temp qw(tempdir);
use Test::More;

require_ok('CCFE::Theme') or BAIL_OUT('cannot load CCFE::Theme');

# ---- pure maps ---------------------------------------------------------
is( CCFE::Theme::color_number('red'),     1,  'red -> COLOR_RED' );
is( CCFE::Theme::color_number('cyan'),    6,  'cyan -> COLOR_CYAN' );
is( CCFE::Theme::color_number('-'),       -1, "'-' -> terminal default" );
is( CCFE::Theme::color_number('default'), -1, "'default' -> terminal default" );
is( CCFE::Theme::color_number(undef),     -1, 'undef -> terminal default' );
is( CCFE::Theme::color_number('nosuchcolour'),
    undef, 'unknown colour -> undef' );

is( CCFE::Theme::pair_number('red'),  1, 'red is pair 1' );
is( CCFE::Theme::pair_number('cyan'), 6, 'cyan is pair 6' );
is( CCFE::Theme::pair_number('mauve'), undef, 'unknown colour -> no pair' );
is_deeply(
    [ CCFE::Theme::pair_names() ],
    [qw( red green yellow blue magenta cyan white )],
    'standard pair order'
);

# ---- dynamic foreground/background pairs -------------------------------
my $p1 = CCFE::Theme::pair_for( 'white', 'blue' );
cmp_ok( $p1, '>=', 8, 'a fg/bg pair is numbered after the 7 standard pairs' );
is( CCFE::Theme::pair_for( 'white', 'blue' ),
    $p1, '  the same fg/bg combo reuses its pair number' );
isnt( CCFE::Theme::pair_for( 'yellow', 'red' ),
    $p1, '  a different combo gets a different pair number' );
is( CCFE::Theme::pair_for( 'nosuchcolour', 'blue' ),
    0, '  an unknown colour degrades to the default pair (0)' );
my %defs = map { $_->[0] => "$_->[1]:$_->[2]" } CCFE::Theme::dynamic_pairs();
is(
    $defs{$p1},
    CCFE::Theme::color_number('white') . ':'
      . CCFE::Theme::color_number('blue'),
    '  dynamic_pairs() records the (fg,bg) for each allocated pair'
);

# ---- end-to-end: configured colour attributes paint in colour ----------
SKIP: {
    my $n = 4;
    eval { require CCFE::Test::Pty; 1 }
      or skip( 'pty helper unavailable', $n );
    skip( 'no Linux pseudo-terminal', $n ) unless CCFE::Test::Pty->available;
    skip( 'Curses not installed', $n ) unless eval { require Curses; 1 };
    my $src = "$Bin/..";
    skip( 'no installer', $n ) unless -f "$src/install.sh";

    my $prefix = tempdir( CLEANUP => 1 );
    my $log    = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
    skip( "install failed: $log", $n ) unless $? == 0 && -x "$prefix/bin/ccfe";

    # Colour the run-output's stdout lines green, and give the menu screen a
    # colour theme (cyan items, a bold-reverse yellow selection) -- the
    # mechanism a SMIT-style instance config would use.
    my $conf = "$prefix/etc/ccfe.conf";
    my $txt  = do { local ( @ARGV, $/ ) = $conf; <> };
    $txt =~ s/^\s*stdout_attr\s*=.*$/  stdout_attr = COLOR_PAIR(2)/m;
    $txt =~ s/^menu_global \{/menu_global {\n  screen_attr   = color_pair('white', 'blue')\n  selected_attr = COLOR_PAIR(3) | A_REVERSE | A_BOLD/m;
    open( my $fh, '>', $conf ) or skip( "rewrite conf: $!", $n );
    print {$fh} $txt;
    close($fh);

    # An ANSI foreground-colour SGR: ESC [ ... 3X (m|;)  -- 32 = green.
    my $colour_re = qr/\x1b\[[0-9;]*3[0-7][;m]/;

    # An ANSI background-colour SGR: ESC [ ... 4X (m|;)  -- 44 = blue.
    my $bg_re = qr/\x1b\[[0-9;]*4[0-7][;m]/;

    # Open a shortcut, optionally press Enter, return the raw terminal bytes.
    my $drive = sub {
        my ( $name, %opt ) = @_;
        local $ENV{NO_COLOR} = $opt{NO_COLOR} if exists $opt{NO_COLOR};
        my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", $name );
        $pty->pump(1.2);
        if ( $opt{enter} ) { $pty->send("\n"); $pty->pump(1.2); }
        my $raw = $pty->raw;
        $pty->send("\033");
        $pty->pump(0.3);
        $pty->send("\033");
        $pty->pump(0.3);
        $pty->send("\033");
        $pty->wait(3);
        return $raw;
    };

    # run: output painted via stdout_attr
    like( $drive->( 'ccfe', enter => 1 ), $colour_re,
        'a configured COLOR_PAIR paints run output in colour' );

    # the menu screen itself painted via the menu_global theme
    my $menu_raw = $drive->('sysmon');
    like( $menu_raw, $colour_re,
        'a menu_global colour theme paints the menu in colour' );

    # a color_pair('fg','bg') screen_attr paints a background colour (panel look)
    like( $menu_raw, $bg_re,
        'color_pair() gives the menu a background colour (panelled look)' );

    # NO_COLOR forces monochrome
    unlike( $drive->( 'ccfe', enter => 1, NO_COLOR => 1 ), $colour_re,
        'NO_COLOR disables colour (monochrome output)' );
}

done_testing();
