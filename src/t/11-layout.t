#!/usr/bin/perl
#
# Compact form layout (ROADMAP M6): in NORMAL layout the value column sits
# just right of the page's longest label (a short dot run, ~4 columns), not
# right-aligned to the screen edge.  This keeps forms narrow so values stay
# on-screen on smaller terminals.  A value too wide to fit at that shared
# column slides right far enough to fit, so a long label combined with a wide
# value can never push the value off the screen (which would leave the form
# unposted -- the builder-form regression this guards).
#
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/lib";
use File::Temp qw(tempdir);
use Test::More;

my $src = "$Bin/..";

eval { require CCFE::Test::Pty; 1 } or plan skip_all => "pty helper: $@";
plan skip_all => 'no Linux pseudo-terminal' unless CCFE::Test::Pty->available;
plan skip_all => 'Curses not installed'     unless eval { require Curses; 1 };
plan skip_all => 'no installer' unless -f "$src/install.sh";

my $prefix = tempdir( CLEANUP => 1 );
my $ilog   = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
plan skip_all => "install failed: $ilog"
  unless $? == 0 && -x "$prefix/bin/ccfe";

plan tests => 8;

my $objs   = "$prefix/share/ccfe/objects/ccfe";
my $logf   = "$prefix/log/" . ( $ENV{USER} || getpwuid($<) ) . ".log";

# Run a form under -d on a pty and return its screen plus the debug log.
sub run_form {
    my ( $name, $cols, $rows, @resizes ) = @_;
    unlink $logf;
    my $pty = CCFE::Test::Pty->spawn( $cols, $rows, "$prefix/bin/ccfe", '-d',
        $name );
    $pty->pump(1.3);
    for my $wh (@resizes) {
        $pty->resize( @$wh );
        $pty->pump(1.0);
    }
    my $screen = $pty->screen;
    $pty->send("\033");
    $pty->pump(0.3);
    $pty->send("\033");
    $pty->wait(3);
    my $log = '';
    if ( open( my $fh, '<', $logf ) ) { local $/; $log = <$fh>; close($fh) }
    return ( $screen, $log );
}

# --- a normal form: value column is right-aligned (expands to the width) -----
# Short labels, short values: the value is right-aligned to the screen edge
# (classic SMIT), so it uses the available width rather than hugging the
# labels.  The form's natural width (the resize trace's max_right) is therefore
# close to the build width, not a narrow column near the labels.
{
    open( my $fh, '>', "$objs/compact.form" ) or die "write: $!";
    print {$fh} "title { Wideform }\n";
    print {$fh}
      "field {\n  id    = F$_\n  len   = 5\n  type  = STRING\n  label = Item $_\n}\n"
      for 1 .. 6;
    print {$fh} "action { run:true }\n";
    close($fh);

    my ( $screen, $log ) = run_form( 'compact', 80, 24, [ 110, 30 ] );
    my @mr = $log =~ /max_right=(\d+)/g;
    ok( scalar @mr, 'resize traced the form width (max_right)' );
    cmp_ok( $mr[0], '>', 60,
        "  value column is right-aligned, using the width (max_right=$mr[0])" );

    # Horizontal re-flow: after a resize the value column re-right-aligns to the
    # NEW width, so the form's right edge tracks the terminal (it does not stay
    # pinned at the build width).
    cmp_ok( $mr[-1], '>', 100,
        "  value column re-expands to the new width on resize (max_right=$mr[-1])"
    );
}

# --- a long label + a wide value still posts (no E_NO_ROOM) -----------------
# Longest label ~34 cols and a 40-wide value would overflow an 80-col screen
# if the value were planted at the shared column; it must slide right to fit so
# post_form succeeds.  This is exactly the builder newmenu shape.
{
    open( my $fh, '>', "$objs/wide.form" ) or die "write: $!";
    print {$fh} "title { Wide }\n";
    print {$fh}
      "field {\n  id    = NAME\n  len   = 24\n  type  = STRING\n  label = A fairly long descriptive field label\n}\n";
    print {$fh}
      "field {\n  id    = BODY\n  len   = 40\n  type  = STRING\n  label = Body\n}\n";
    print {$fh} "action { run:true }\n";
    close($fh);

    my ( $screen, $log ) = run_form( 'wide', 80, 24 );
    my @posts = $log =~ /do_form: post_form => (-?\d+)/g;
    ok( scalar @posts, 'initial build traced post_form' );
    is( ( scalar grep { $_ != 0 } @posts ),
        0,
        '  long label + wide value still posts at 80 cols (no E_NO_ROOM)' );
}

# --- a label too long to sit beside its value wraps -------------------------
# A 43-col label with a 40-wide value cannot fit side by side on 80 columns, so
# the label wraps onto its own line(s) and the value drops to the row below.
# The form must still post (no E_NO_ROOM), and survive a resize.
{
    open( my $fh, '>', "$objs/wrap.form" ) or die "write: $!";
    print {$fh} "title { Wrap }\n";
    print {$fh}
      "field {\n  id    = HOST\n  len   = 40\n  type  = STRING\n  label = Fully qualified primary DNS server hostname\n}\n";
    print {$fh}
      "field {\n  id    = PORT\n  len   = 6\n  type  = NUMERIC\n  label = Port\n}\n";
    print {$fh} "action { run:true }\n";
    close($fh);

    my ( $screen, $log ) = run_form( 'wrap', 80, 24, [ 110, 30 ] );
    like( $log, qr/wrapped label "HOST"/,
        'a label too long to fit beside its value wraps' );
    my @posts = $log =~ /post_form => (-?\d+)/g;
    ok( scalar @posts, '  wrapped form posts (build and resize)' );
    is( ( scalar grep { $_ != 0 } @posts ),
        0, '  wrapped form never fails post_form, before or after resize' );
}
