package CCFE::FormFile;

# Pure parser for CCFE `.form` content (ROADMAP M7, REFACTOR.md §3).
#
# parse($text, \%opt) turns the (comment-stripped, concatenated) text of a form
# -- title/top/bottom/path/init/action blocks plus any number of field and
# separator blocks -- into a plain data structure, with no terminal, no globals
# and no I/O.  load_form() in ccfe.pl keeps the file finding/reading and owns
# the rest: the (effectful) command/boolean default processing, the
# $COLS-dependent separator label formatting, select-item resolution and the
# side effects on %form.  So this module is just the parse, and the parser
# tests drive it directly.
#
# \%opt supplies the lookup maps and constants the parser must not own:
#   { bool      => \%bool_vals,       # "yes"/"no"/... -> 1/0
#     type      => \%type_vals,       # "string"/...   -> field type constant
#     sep_type  => \%sep_type_vals,   # "line"/...     -> separator subtype
#     separator => $SEPARATOR,        # the field type constant for separators
#     no        => $NO }              # the boolean-false constant
#
# Returns ($form, $status, \@warnings, $field_count):
#   $form  = { title, top => [..], bottom => [..], path, init, action,
#              fields => [ { id, label, len, type, ... } ] }
#   $status = 'ok' | 'syntax_error'
#   each separator field carries {sep_type} and the raw {label}; the caller
#   applies the $COLS-dependent centring / rule-line formatting.

use v5.36;
use Text::Balanced qw(extract_bracketed);

our $VERSION = '2.1';

my %SCALAR_BLOCK =
  ( title => 'title', path => 'path', init => 'init', action => 'action' );
my %LIST_BLOCK = ( top => 'top', bottom => 'bottom' );

# --- field attribute handlers: name => sub($field, $value, $ctx) ---------
my %FIELD_ATTR;

# plain string attributes: stored verbatim
for my $a (qw( label len htab vtab option default list_cmd )) {
    $FIELD_ATTR{$a} = sub ( $f, $v, $ctx ) { $f->{$a} = $v; return };
}

# boolean attributes: validated against the caller's bool map
for my $a (qw( hscroll enabled hidden required persist ignore_unchgd )) {
    $FIELD_ATTR{$a} = sub ( $f, $v, $ctx ) {
        my $b = $ctx->{bool}{ lc $v };
        defined $b
          ? ( $f->{$a} = $b )
          : _bad( $ctx, "wrong value \"$v\" for \"$a\" attribute" );
        return;
    };
}

$FIELD_ATTR{type} = sub ( $f, $v, $ctx ) {
    my $t = $ctx->{type}{ lc $v };
    defined $t
      ? ( $f->{type} = $t )
      : _bad( $ctx, "unknown field type \"$v\"" );
    return;
};

$FIELD_ATTR{list_sep} = sub ( $f, $v, $ctx ) {
    $v =~ /"([ ,;:])"/
      ? ( $f->{list_sep} = $1 )
      : _bad( $ctx, "syntax error \"$v\" in \"list_sep\" attribute" );
    return;
};

# --- separator attribute handlers ---------------------------------------
my %SEP_ATTR = (
    text => sub ( $f, $v, $ctx ) { $f->{label} = $v; return },
    htab => sub ( $f, $v, $ctx ) { $f->{htab}  = $v; return },
    vtab => sub ( $f, $v, $ctx ) { $f->{vtab}  = $v; return },
    type => sub ( $f, $v, $ctx ) {
        my $t = $ctx->{sep_type}{ lc $v };
        defined $t
          ? ( $f->{sep_type} = $t )
          : _bad( $ctx, "unknown separator type \"$v\"" );
        return;
    },
);

sub _bad ( $ctx, $msg ) {
    push @{ $ctx->{warn} }, $msg;
    ${ $ctx->{status} } = 'syntax_error';
    return;
}

# A field's `key = value` lines into $form->{fields}[ fc ].
sub _block_field ( $form, $val, $ctx ) {
    my $fc = ${ $ctx->{fc} };
    for my $line ( split /\s*\n\s*/, $val ) {
        my ( $ak, $av ) = split /\s*=\s*/, $line, 2;
        my $a = lc( $ak // '' );
        my $f = ( $form->{fields}[$fc] //= {} );
        if ( $a eq 'id' ) {
            _dup_id( $form, $fc, $av, $ctx, 'field ID' );
            $f->{id} = $av;
        }
        elsif ( my $h = $FIELD_ATTR{$a} ) {
            $h->( $f, $av, $ctx );
        }
        else {
            _bad( $ctx, "unknown field attribute \"$ak\"" );
        }
    }
    ${ $ctx->{fc} }++;
    return;
}

# A separator block: parse its attributes, then apply the fixed separator
# defaults and an auto id.  The $COLS-dependent label formatting is the
# caller's job (it is layout, not parsing).
sub _block_separator ( $form, $val, $ctx ) {
    my $fc = ${ $ctx->{fc} };
    my $f  = ( $form->{fields}[$fc] //= {} );
    for my $line ( split /\s*\n\s*/, $val ) {
        my ( $ak, $av ) = split /\s*=\s*/, $line, 2;
        my $a = lc( $ak // '' );
        if ( $a eq 'id' ) {
            _dup_id( $form, $fc, $av, $ctx, 'field ID in separator' );
            $f->{id} = $av;
        }
        elsif ( my $h = $SEP_ATTR{$a} ) {
            $h->( $f, $av, $ctx );
        }
        else {
            _bad( $ctx, "unknown separator attribute \"$ak\"" );
        }
    }
    my $false = $ctx->{no};
    $f->{type}    = $ctx->{separator};
    $f->{len}     = 1;
    $f->{enabled} = $f->{required} = $f->{persist}       = $false;
    $f->{hidden}  = $f->{hscroll}  = $f->{ignore_unchgd} = $false;
    $f->{option}  = $f->{default}  = $f->{list_cmd}      = '';
    $f->{id} //= sprintf 'CCFEFSEP%03d', ++${ $ctx->{sc} };
    ${ $ctx->{fc} }++;
    return;
}

sub _dup_id ( $form, $fc, $av, $ctx, $what ) {
    push @{ $ctx->{warn} }, "duplicated $what \"$av\""
      for grep { ( $form->{fields}[$_]{id} // '' ) eq $av } 0 .. $fc - 1;
    return;
}

my %BLOCK = ( field => \&_block_field, separator => \&_block_separator );

sub parse ( $text, $opt ) {
    my %form   = ( top => [], fields => [] );
    my $status = 'ok';
    my $fc     = 0;
    my $sc     = 0;
    my %ctx    = (
        bool      => $opt->{bool}     // {},
        type      => $opt->{type}     // {},
        sep_type  => $opt->{sep_type} // {},
        separator => $opt->{separator},
        no        => $opt->{no},
        warn      => [],
        status    => \$status,
        fc        => \$fc,
        sc        => \$sc,
    );

    my ( $val, $key );
    ( $val, undef, $key ) = extract_bracketed( $text, '{', '\s*[a-zA-Z]*\s*' );
    while ($key) {
        $val =~ s/^\{\s*//;
        $val =~ s/\s*\n?\s*\}$//;
        $key =~ s/^\s+//;
        $key =~ s/\s+$//;
        my $k = lc $key;

        if ( my $h = $BLOCK{$k} ) {
            $h->( \%form, $val, \%ctx );
        }
        elsif ( exists $SCALAR_BLOCK{$k} ) {
            $form{ $SCALAR_BLOCK{$k} } = $val;
        }
        elsif ( exists $LIST_BLOCK{$k} ) {
            $form{ $LIST_BLOCK{$k} } = [ split /\s*\n\s*/, $val, 2 ];
        }
        else {
            _bad( \%ctx, "unknown form attribute \"$key\"" );
        }

        ( $val, undef, $key ) =
          extract_bracketed( $text, '{', '\s*[a-zA-Z]*\s*' );
    }
    $status = 'syntax_error' if !pos($text);
    return ( \%form, $status, $ctx{warn}, $fc );
}

1;

__END__

=head1 NAME

CCFE::FormFile - pure parser for CCFE F<.form> content

=head1 SYNOPSIS

    use CCFE::FormFile;
    my ($form, $status, $warnings, $field_count) =
        CCFE::FormFile::parse($form_text, \%opt);

=head1 DESCRIPTION

Turns the (comment-stripped, concatenated) text of a form - title/top/bottom/
path/init/action blocks plus any number of field and separator blocks - into a
plain data structure, with no terminal, no globals and no I/O. C<load_form> in
F<ccfe.pl> keeps the file finding/reading and owns the rest: the (effectful)
command/boolean default processing, the C<$COLS>-dependent separator label
formatting, select-item resolution and the side effects on C<%form>. This
module is just the parse, and the parser tests drive it directly.

=head1 FUNCTIONS

=head2 parse

    my ($form, $status, $warnings, $field_count) =
        CCFE::FormFile::parse($text, \%opt);

C<\%opt> supplies the lookup maps and constants the parser must not own:

    { bool      => \%bool_vals,       # "yes"/"no"/... -> 1/0
      type      => \%type_vals,       # "string"/...   -> field type constant
      sep_type  => \%sep_type_vals,   # "line"/...     -> separator subtype
      separator => $SEPARATOR,        # the field type constant for separators
      no        => $NO }              # the boolean-false constant

Returns a four-element list:

=over 4

=item C<$form>

C<< { title, top => [..], bottom => [..], path, init, action,
fields => [ { id, label, len, type, ... } ] } >>. Each separator field carries
C<sep_type> and the raw C<label>; the caller applies the C<$COLS>-dependent
centring / rule-line formatting.

=item C<$status>

C<'ok'> or C<'syntax_error'>.

=item C<$warnings>

An arrayref of human-readable notes (duplicate id, unknown attribute, bad
value, ...).

=item C<$field_count>

The number of field and separator blocks seen.

=back

=head1 SEE ALSO

L<ccfe_form(5)>, L<CCFE::Layout>, L<CCFE::Action>, F<REFACTOR.md> section 3.

=cut
