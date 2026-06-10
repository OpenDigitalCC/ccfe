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

# ---- end-to-end: a configured colour attribute paints in colour --------
SKIP: {
    eval { require CCFE::Test::Pty; 1 }
      or skip( 'pty helper unavailable', 2 );
    skip( 'no Linux pseudo-terminal', 2 ) unless CCFE::Test::Pty->available;
    skip( 'Curses not installed', 2 ) unless eval { require Curses; 1 };
    my $src = "$Bin/..";
    skip( 'no installer', 2 ) unless -f "$src/install.sh";

    my $prefix = tempdir( CLEANUP => 1 );
    my $log    = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
    skip( "install failed: $log", 2 ) unless $? == 0 && -x "$prefix/bin/ccfe";

    # Colour the run-output's stdout lines green (COLOR_PAIR(2)).
    my $conf = "$prefix/etc/ccfe.conf";
    my $txt  = do { local ( @ARGV, $/ ) = $conf; <> };
    $txt =~ s/^\s*stdout_attr\s*=.*$/  stdout_attr = COLOR_PAIR(2)/m;
    open( my $fh, '>', $conf ) or skip( "rewrite conf: $!", 2 );
    print {$fh} $txt;
    close($fh);

    # `ccfe ccfe` opens the install-test menu whose first item is
    # run:cat it_works.txt -- press Enter to show that output in colour.
    my $drive = sub {
        my (%env) = @_;
        local $ENV{NO_COLOR} = $env{NO_COLOR} if exists $env{NO_COLOR};
        my $pty = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", 'ccfe' );
        $pty->pump(1.2);
        $pty->send("\n");
        $pty->pump(1.2);
        my $raw = $pty->raw;
        $pty->send("\033");
        $pty->pump(0.3);
        $pty->send("\033");
        $pty->pump(0.3);
        $pty->send("\033");
        $pty->wait(3);
        return $raw;
    };

    # An ANSI foreground-colour SGR: ESC [ ... 3X (m|;)  -- 32 = green.
    my $colour_re = qr/\x1b\[[0-9;]*3[0-7][;m]/;

    my $raw_colour = $drive->();
    like( $raw_colour, $colour_re,
        'a configured COLOR_PAIR paints the output in colour' );

    my $raw_mono = $drive->( NO_COLOR => 1 );
    unlike( $raw_mono, $colour_re,
        'NO_COLOR disables colour (monochrome output)' );
}

done_testing();
