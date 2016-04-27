package Pcore::HTTP::Server::Writer;

use Pcore -class;

has server => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server'], required => 1, weak_ref => 1 );
has h      => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'],   required => 1, weak_ref => 1 );
has keep_alive => ( is => 'ro', isa => PositiveOrZeroInt, required => 1 );
has psgi_input => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server::Reader'], required => 1 );
has buf_size => ( is => 'ro', isa => PositiveOrZeroInt, default => 65_536 );

has buf => ( is => 'ro', isa => Str, default => q[], init_arg => undef );

sub write ( $self, $data ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    $self->{buf} .= ref $data ? $data->$* : $data;

    if ( length $self->{buf} >= $self->{buf_size} ) {
        $self->{server}->_write_buf( $self->{h}, \( sprintf( '%x', length $self->{buf} ) . $CRLF . $self->{buf} . $CRLF ) );

        $self->{buf} = q[];
    }

    return;
}

# TODO write possible triling headers
sub close ( $self, $trailing_headers = undef ) {    ## no critic qw[NamingConventions::ProhibitAmbiguousNames Subroutines::ProhibitBuiltinHomonyms]

    # write last chunk
    $self->{server}->_write_buf( $self->{h}, \( ( length $self->{buf} ? sprintf( '%x', length $self->{buf} ) . $CRLF . $self->{buf} . $CRLF : q[] ) . 0 . $CRLF . $CRLF ) );

    if ($trailing_headers) {

        # TODO write trailing headers, if client is supported
    }

    $self->{server}->_finish_request( $self->{h}, $self->{keep_alive}, $self->{psgi_input} );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 29                   | ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server::Writer

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
