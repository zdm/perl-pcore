package Pcore::Core::Dump;

use Pcore -export => {
    CORE    => [qw[dump filedump ffiledump]],
    DEFAULT => [qw[dump]],
};
use Pcore::Core::Dump::Dumper;

sub dump {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    my %args = (
        color       => 1,
        indent      => 4,
        dump_method => 'TO_DUMP',
        splice( @_, 1 ),
    );

    return q[$VAR = ] . Pcore::Core::Dump::Dumper->new( \%args )->run( $_[0] );
}

sub filedump {
    my $self = shift;

    return $self->ffiledump( 'default.log', @_ );
}

sub ffiledump ( $self, $filename, @ ) {
    P->file->append_text( $ENV->{LOG_DIR} . $filename, Pcore::Core::Dump::dump( @_, color => 0 ), $LF );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    1 │ 17                   │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Dump

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
