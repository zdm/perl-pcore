package Pcore::HTTP::Server::Reader;

use Pcore -class;

has server => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server'], required => 1, weak_ref => 1 );
has h      => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'],   required => 1, weak_ref => 1 );
has chunked        => ( is => 'ro', isa => Bool,              required => 1 );
has content_length => ( is => 'ro', isa => PositiveOrZeroInt, required => 1 );
has has_data       => ( is => 'ro', isa => Bool,              required => 1 );

# TODO deal with error message
sub read ( $self, $cb ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    if ( !$self->{has_data} ) {
        $cb->( undef, $self->{content_length} );
    }
    else {
        $self->{h}->read_http_body(
            sub ( $h, $buf_ref, $total_bytes_readed, $error_message ) {
                $self->{content_length} = $total_bytes_readed if !$self->{chunked};

                $self->{has_data} = 0 if !$buf_ref;

                return $cb->( $buf_ref, $total_bytes_readed );
            },
            chunked  => $self->{chunked},
            length   => $self->{content_length},
            headers  => 0,
            buf_size => 65_536,
        );
    }

    return;
}

sub seek ($self) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    die q[Seek isn't possible for unbuffered stream];
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server::Reader

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
