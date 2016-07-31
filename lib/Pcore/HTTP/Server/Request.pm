package Pcore::HTTP::Server::Request;

use Pcore -class, -const;

P->init_demolish(__PACKAGE__);

const our $HTTP_SERVER_RESPONSE_NEW              => 0;
const our $HTTP_SERVER_RESPONSE_HEADERS_FINISHED => 1;
const our $HTTP_SERVER_RESPONSE_BODY_STARTED     => 2;
const our $HTTP_SERVER_RESPONSE_FINISHED         => 3;

has _server => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server'], required => 1 );
has _h      => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'],   required => 1 );
has env => ( is => 'ro', isa => HashRef, required => 1 );

has _keep_alive => ( is => 'lazy', isa => PositiveOrZeroInt, init_arg => undef );

has _response_status => ( is => 'ro', isa => Bool, default => $HTTP_SERVER_RESPONSE_NEW, init_arg => undef );

sub DEMOLISH ( $self, $global ) {
    return;
}

sub _build__keep_alive($self) {
    my $env = $self->{env};

    my $keep_alive = $self->{_server}->{keep_alive};

    if ($keep_alive) {
        if ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.1' ) {
            $keep_alive = 0 if $env->{HTTP_CONNECTION} && $env->{HTTP_CONNECTION} =~ /\bclose\b/smi;
        }
        elsif ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.0' ) {
            $keep_alive = 0 if !$env->{HTTP_CONNECTION} || $env->{HTTP_CONNECTION} !~ /\bkeep-?alive\b/smi;
        }
        else {
            $keep_alive = 0;
        }
    }

    return $keep_alive;
}

sub write_headers ( $self, $status, $headers = undef ) {
    die qq[Headers already written] if $self->{_response_status} > $HTTP_SERVER_RESPONSE_NEW;

    $self->{_response_status} = $HTTP_SERVER_RESPONSE_HEADERS_FINISHED;

    $self->{_server}->_write_psgi_response( $self->{_h}, [ $status, $headers // [] ], $self->_keep_alive, 1 );

    return $self;
}

# TODO implement buffered chunk write
sub write ( $self, @ ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    if ( !$self->{_response_status} ) {
        $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

        $self->{_server}->_write_psgi_response( $self->{_h}, [ splice @_, 1 ], $self->_keep_alive, 0 );

        $self->{_server}->_finish_request( $self->{_h}, $self->_keep_alive );
    }
    else {
        die if $self->{_response_status} == $HTTP_SERVER_RESPONSE_HEADERS_FINISHED;

        # TODO implement buffered chunk write
        $self->{_server}->_write_psgi_response( $self->{_h}, \$_[1] );
    }

    return $self;
}

# TODO inplement writer close method
sub finish ( $self, $trailing_headers = undef ) {

    # die if !$self->{_headers_written};

    # die if $self->{_body_written};

    $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

    $self->{_server}->_finish_request( $self->{_h}, $self->_keep_alive );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 45                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
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
