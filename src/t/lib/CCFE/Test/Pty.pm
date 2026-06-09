package CCFE::Test::Pty;

# Minimal, dependency-free pseudo-terminal driver for the CCFE test suite.
#
# CCFE is a full-screen curses program: it will not initialise unless stdin
# and stdout are a real terminal, so it cannot be exercised end-to-end with
# ordinary pipes.  The usual answer (IO::Pty / Expect) is not available in
# this build -- the whole point of v1.60 was to drop to "standard packages
# only" -- so this helper opens a Linux pty itself using nothing but core
# POSIX and the /dev/ptmx ioctls.
#
# It is deliberately Linux-specific (the ioctl request numbers below are the
# Linux/glibc values).  t/03-tty-smoke.t skips itself on other platforms or
# if /dev/ptmx is missing (e.g. a build sandbox with no devpts).
#
# Usage:
#     my $pty = CCFE::Test::Pty->spawn(80, 24, @argv);
#     $pty->pump(1.0);          # read whatever the child paints
#     $pty->send("q");          # send keystrokes
#     my ($exit, $signal) = $pty->wait;
#     my $screen = $pty->screen;   # captured output, escape codes stripped
#
# Only core modules are used (POSIX, IO::Handle, Time::HiRes -- all core).

use strict;
use warnings;
use POSIX qw(setsid dup2 _exit);
use Time::HiRes qw(time sleep);

# Linux ioctl request numbers.
use constant {
    TIOCSPTLCK => 0x40045431,    # lock/unlock the pty slave
    TIOCGPTN   => 0x80045430,    # get the pty number
    TIOCSWINSZ => 0x5414,        # set window size
};

# Is a pty even possible here?  Used by tests to decide whether to skip.
sub available {
    return ( $^O eq 'linux' && -e '/dev/ptmx' && -d '/dev/pts' ) ? 1 : 0;
}

sub spawn {
    my ( $class, $cols, $rows, @argv ) = @_;

    open( my $master, '+<', '/dev/ptmx' ) or die "open /dev/ptmx: $!";
    $master->autoflush(1);

    my $unlock = pack( 'i', 0 );
    ioctl( $master, TIOCSPTLCK, $unlock ) or die "unlock pty: $!";

    my $nbuf = pack( 'i', 0 );
    ioctl( $master, TIOCGPTN, $nbuf ) or die "get pty number: $!";
    my $slave_path = '/dev/pts/' . unpack( 'i', $nbuf );

    my $winsize = pack( 'S4', $rows, $cols, 0, 0 );
    ioctl( $master, TIOCSWINSZ, $winsize );    # best-effort

    my $pid = fork();
    die "fork: $!" unless defined $pid;

    if ( $pid == 0 ) {
        # Child: become a session leader so the slave becomes our
        # controlling terminal, wire it to the three standard handles,
        # and exec the program under test.
        setsid();
        open( my $slave, '+<', $slave_path ) or _exit(126);
        dup2( fileno($slave), 0 );
        dup2( fileno($slave), 1 );
        dup2( fileno($slave), 2 );
        $ENV{TERM} = 'xterm' unless defined $ENV{TERM} && length $ENV{TERM};
        exec(@argv) or _exit(127);
    }

    return bless {
        master => $master,
        pid    => $pid,
        buf    => '',
        reaped => 0,
        status => undef,
    }, $class;
}

# Read everything the child emits for up to $secs seconds, accumulating it.
sub pump {
    my ( $self, $secs ) = @_;
    my $fd  = fileno( $self->{master} );
    my $end = time + $secs;
    while ( time < $end ) {
        my $rin = '';
        vec( $rin, $fd, 1 ) = 1;
        my $nfound = select( my $rout = $rin, undef, undef, 0.2 );
        next unless $nfound && vec( $rout, $fd, 1 );
        my $chunk;
        my $r = sysread( $self->{master}, $chunk, 65536 );
        last if !defined $r || $r == 0;    # EOF: child closed the pty
        $self->{buf} .= $chunk;
    }
    return $self;
}

sub send {
    my ( $self, $bytes ) = @_;
    syswrite( $self->{master}, $bytes );
    return $self;
}

# Reap the child (if it has exited) and return (exit_code, signal).
# Sends SIGKILL as a backstop if it is still alive after a grace period.
sub wait {
    my ( $self, $grace ) = @_;
    return @{ $self->{status} } if $self->{reaped};
    $grace = defined $grace ? $grace : 3;

    my $end = time + $grace;
    my $gone;
    while ( time < $end ) {
        $gone = waitpid( $self->{pid}, POSIX::WNOHANG() );
        last if $gone == $self->{pid} || $gone == -1;
        sleep 0.1;
    }
    if ( !$gone || ( $gone != $self->{pid} && $gone != -1 ) ) {
        kill 'KILL', $self->{pid};
        waitpid( $self->{pid}, 0 );
    }

    my $st     = $?;
    my $signal = $st & 127;
    my $exit   = $st >> 8;
    $self->{reaped} = 1;
    $self->{status} = [ $exit, $signal ];
    return ( $exit, $signal );
}

# Captured output with terminal escape sequences and control characters
# stripped, for readable substring assertions.
sub screen {
    my ($self) = @_;
    my $s = $self->{buf};
    $s =~ s/\x1b\[[0-9;?]*[ -\/]*[\@-~]//g;    # CSI sequences
    $s =~ s/\x1b[()][A-B0-2]//g;               # charset selection
    $s =~ s/\x1b[=>]//g;                        # keypad mode
    $s =~ s/\x1b\][^\x07]*\x07//g;              # OSC ... BEL
    $s =~ s/[\x00-\x08\x0b-\x1f\x7f]//g;        # remaining control chars (keep \n,\t)
    return $s;
}

# Raw, unfiltered capture.
sub raw { return $_[0]->{buf} }

sub DESTROY {
    my ($self) = @_;
    return if $self->{reaped};
    kill 'KILL', $self->{pid} if $self->{pid};
    waitpid( $self->{pid}, POSIX::WNOHANG() ) if $self->{pid};
}

1;
