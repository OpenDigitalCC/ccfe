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
