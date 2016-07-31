package Pcore::HTTP::Server::Request;

use Pcore -class, -const;

P->init_demolish(__PACKAGE__);

const our $HTTP_SERVER_RESPONSE_NEW              => 0;
const our $HTTP_SERVER_RESPONSE_HEADERS_FINISHED => 1;
const our $HTTP_SERVER_RESPONSE_BODY_STARTED     => 2;
const our $HTTP_SERVER_RESPONSE_FINISHED         => 3;

has env       => ( is => 'ro', isa => HashRef, required => 1 );
has responder => ( is => 'ro', isa => CodeRef, required => 1 );

has _response_status => ( is => 'ro', isa => Bool, default => $HTTP_SERVER_RESPONSE_NEW, init_arg => undef );

sub DEMOLISH ( $self, $global ) {
    return;
}

sub write_headers ( $self, $status, $headers = undef ) {
    die qq[Headers already written] if $self->{_response_status} > $HTTP_SERVER_RESPONSE_NEW;

    $self->{_response_status} = $HTTP_SERVER_RESPONSE_HEADERS_FINISHED;

    $self->{responder} = $self->{responder}->( [ $status, $headers // [] ] );

    return $self;
}

sub write ( $self, @ ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    if ( !$self->{_headers_written} ) {
        $self->{_headers_written} = 1;

        $self->{_body_written} = 1;

        $self->{responder}->( [ splice @_, 1 ] );
    }
    else {
        die if !$self->{_headers_written};

        die if $self->{_body_written};

        $self->{responder}->write( $_[1] );
    }

    return $self;
}

sub finish ( $self, $trailing_headers = undef ) {
    die if !$self->{_headers_written};

    die if $self->{_body_written};

    $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

    $self->{responder}->close($trailing_headers);

    undef $self->{responder};

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 22                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
