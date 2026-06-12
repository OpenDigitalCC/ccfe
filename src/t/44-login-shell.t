#!/usr/bin/perl
#
# CCFE-as-login-shell setup ("CCFE as shell on system login").
#
# ccfe-login manages a marker-delimited block in a shell profile that launches
# the CCFE menu on an interactive login, and the `-R`/--restricted flag forces
# the kiosk sandbox for a run.  This drives both: the ccfe-login install /
# status / idempotency / uninstall cycle, its refusals (restricted session,
# non-root system install), and -- via a pty -- that `ccfe -R` actually puts the
# session in restricted mode (it exports CCFE_RESTRICTED to children).
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
my $log    = `cd "$src" && sh install.sh -b -p "$prefix" 2>&1`;
plan skip_all => "install failed: $log" unless $? == 0 && -x "$prefix/bin/ccfe";

my $login = "$prefix/bin/ccfe-login";
plan skip_all => 'ccfe-login not installed' unless -x $login;

plan tests => 10;

sub slurp {
    my ($path) = @_;
    open( my $fh, '<', $path ) or return '';
    local $/;
    my $c = <$fh>;
    close($fh);
    return defined $c ? $c : '';
}

# Parse-check the new objects.
for my $obj (qw( login login.d/enable-user login.d/enable-system )) {
    system("$prefix/bin/ccfe -k $obj >/dev/null 2>&1");
    is( $? >> 8, 0, "object $obj parses" );
}

# --- ccfe-login at the shell level ----------------------------------------
my $home = tempdir( CLEANUP => 1 );
my $env  = qq{CCFE_BIN_DIR="$prefix/bin" HOME="$home"};

system(qq{$env "$login" install-user -r >/dev/null 2>&1});
my $prof = -f "$home/.bash_profile" ? "$home/.bash_profile" : "$home/.profile";
my $body = slurp($prof);
like( $body, qr/CCFE login \(managed by ccfe-login\)/,
    'install-user writes the managed block' );
like( $body, qr/\bccfe.* -R\b/, '  restricted kiosk launches ccfe -R' );

like( scalar(`$env "$login" status 2>&1`), qr/ENABLED/,
    'status reports the menu as enabled' );

# Idempotent: a second install leaves exactly one block.
system(qq{$env "$login" install-user >/dev/null 2>&1});
my $n = () = slurp($prof) =~ /CCFE login \(managed/g;
is( $n, 1, 'a second install does not duplicate the block' );

system(qq{$env "$login" uninstall-user >/dev/null 2>&1});
unlike( slurp($prof), qr/CCFE login \(managed/,
    'uninstall-user removes the block' );

# Refusals: a restricted session, and a non-root system install.
system(qq{$env CCFE_RESTRICTED=1 "$login" install-user >/dev/null 2>&1});
isnt( $? >> 8, 0, 'install is refused in a restricted session' );

# --- the -R flag actually activates restricted mode (pty) -----------------
my $objs = "$prefix/share/ccfe/objects/ccfe";
open( my $mf, '>', "$objs/rtest.menu" ) or die "write: $!";
print {$mf} <<'MENU';
title { R test }
item {
  id     = SHOW
  descr  = Show restricted flag
  action = run:echo "RFLAG=[$CCFE_RESTRICTED]"
}
MENU
close($mf);

# Restricted mode prunes WRITABLE object dirs (a kiosk must not load objects a
# user could edit), so make the dir non-writable or -R would find nothing.
chmod 0555, $objs;

my $p = CCFE::Test::Pty->spawn( 80, 24, "$prefix/bin/ccfe", '-R', 'rtest' );
$p->pump(1.2);
$p->send("\r");    # run the action
$p->pump(0.9);
like( $p->screen, qr/RFLAG=\[1\]/,
    'ccfe -R runs the session in restricted mode (CCFE_RESTRICTED=1)' );
$p->send("\e");
$p->pump(0.2);
$p->send("\e");
$p->pump(0.2);

chmod 0755, $objs;    # restore so the tempdir cleanup can remove it
