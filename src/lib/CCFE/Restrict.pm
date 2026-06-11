package CCFE::Restrict;

# CCFE restricted-mode security policy -- the pure "functional core" for
# deciding what a constrained menu user may do.  Every decision is a pure
# function of its arguments (no package globals, no terminal, no I/O), so it
# is unit-testable without loading the curses program; ccfe.pl wraps these in
# thin helpers that add tracing and pass in its configuration.
#
# New CCFE modules target modern Perl: `use v5.36` turns on strict, warnings
# and subroutine signatures, so the legacy un-strict main program does not
# constrain the style of freshly written code.
#
# See REFACTOR.md section 2 ("preventing escape from the menu").

use v5.36;
use File::Basename qw(basename);

our $VERSION = '1.60';

# True if the interactive shell escape (F7) must be refused.
sub denies_shell ($restricted) {
    return $restricted ? 1 : 0;
}

# True if a verb must be refused.  Only system:/exec: are gated -- they hand
# over the terminal or replace the process, the main escape risk (e.g. an
# editor's ":!sh").  They are allowed only when the target program's basename
# is in the allowlist.  run:/menu:/form: are never gated here.
#
#   $allow is an arrayref of permitted program basenames (may be undef/empty).
sub denies_verb ( $restricted, $allow, $verb, $args ) {
    return 0 unless $restricted;
    return 0 unless defined $verb and ( $verb eq 'system' or $verb eq 'exec' );

    my ($prog) = ( $args // '' ) =~ /^\s*(\S+)/;
    return 1 unless defined $prog;
    $prog = basename($prog);
    return 0 if grep { $_ eq $prog } @{ $allow // [] };
    return 1;
}

# Reduce the blast radius of every command CCFE runs: give children a sane
# IFS and strip loader / shell-init hijack variables.  Mutates the passed
# environment hashref (defaults to %ENV).
sub harden_env ( $env = \%ENV ) {
    $env->{IFS} = " \t\n";
    delete @{$env}{qw( BASH_ENV ENV CDPATH )};
    delete $env->{$_} for grep { /^LD_/ } keys %$env;
    return;
}

# POSIX-sh single-quote a value so it becomes one literal shell word, immune
# to metacharacters.  Provided for menu authors / future argv-based execution
# that needs to template an untrusted value into a command string safely.
sub sh_quote ( $s = '' ) {
    $s //= '';
    $s =~ s/'/'\\''/g;
    return "'$s'";
}

1;

__END__

=head1 NAME

CCFE::Restrict - restricted-mode security policy (pure functional core)

=head1 SYNOPSIS

    use CCFE::Restrict;

    next if CCFE::Restrict::denies_shell($restricted);
    if ( CCFE::Restrict::denies_verb($restricted, $allow, 'system', $args) ) {
        # refuse
    }
    CCFE::Restrict::harden_env(\%ENV);
    my $word = CCFE::Restrict::sh_quote($untrusted);

=head1 DESCRIPTION

The decision core for what a constrained (kiosk) menu user may do. Every
decision is a pure function of its arguments - no package globals, no terminal,
no I/O - so it is unit-testable without loading the curses program. F<ccfe.pl>
wraps these in thin helpers that add tracing and pass in its configuration.

See F<REFACTOR.md> section 2 ("preventing escape from the menu").

=head1 FUNCTIONS

=head2 denies_shell

    my $bool = CCFE::Restrict::denies_shell($restricted);

True if the interactive shell escape (F7) must be refused, i.e. whenever
restricted mode is on.

=head2 denies_verb

    my $bool = CCFE::Restrict::denies_verb($restricted, $allow, $verb, $args);

True if an action verb must be refused. Only C<system> and C<exec> are gated -
they hand over the terminal or replace the process, the main escape risk (e.g.
an editor's C<:!sh>). They are allowed only when the target program's basename
appears in C<$allow> (an arrayref of permitted basenames, possibly undef or
empty). C<run>, C<menu> and C<form> are never gated here. Returns false when not
restricted.

=head2 harden_env

    CCFE::Restrict::harden_env(\%ENV);

Reduce the blast radius of every command CCFE runs: set a sane C<IFS> and strip
loader / shell-init hijack variables (C<BASH_ENV>, C<ENV>, C<CDPATH> and any
C<LD_*>). Mutates the passed environment hashref (defaults to C<%ENV>).

=head2 sh_quote

    my $word = CCFE::Restrict::sh_quote($s);

POSIX-sh single-quote a value so it becomes one literal shell word, immune to
metacharacters. For menu authors / argv-based execution that must template an
untrusted value into a command string safely.

=head1 SEE ALSO

L<ccfe(1)>, L<ccfe.conf(5)> (the C<restricted> and C<restricted_allow>
parameters).

=cut
