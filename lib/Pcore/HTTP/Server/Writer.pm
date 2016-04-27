package Pcore::HTTP::Server::Writer;

use Pcore -class;

has server => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server'], required => 1, weak_ref => 1 );
has h      => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'],   required => 1, weak_ref => 1 );
has keep_alive => ( is => 'ro', isa => Bool, required => 1 );

sub write ( $self, $data ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    $self->{h}->push_write( sprintf( '%x', length( ref $data ? $data->$* : $data ) ) . $CRLF . ( ref $data ? $data->$* : $data ) . $CRLF );

    return;
}

# TODO write possible triling headers
sub close ( $self, $trailing_headers = undef ) {    ## no critic qw[NamingConventions::ProhibitAmbiguousNames Subroutines::ProhibitBuiltinHomonyms]

    # write last chunk
    $self->{h}->push_write( 0 . $CRLF . $CRLF );

    if ($trailing_headers) {

        # TODO write trailing headers, if client is supported
    }

    $self->{server}->_finish_request( $self->{h}, $self->{keep_alive} );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 19                   | ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        |
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
