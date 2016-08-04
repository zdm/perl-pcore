package Pcore::HTTP::Server::Request;

use Pcore -class, -const;
use Pcore::HTTP::Status;
use Pcore::Util::List qw[pairs];
use Pcore::Util::Text qw[encode_utf8];

has _server => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server'], required => 1 );
has _h      => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'],   required => 1 );
has env => ( is => 'ro', isa => HashRef, required => 1 );

has _use_keepalive => ( is => 'lazy', isa => Bool, init_arg => undef );

has _response_status => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

const our $HTTP_SERVER_RESPONSE_STARTED  => 1;    # headers written
const our $HTTP_SERVER_RESPONSE_FINISHED => 2;    # body written

P->init_demolish(__PACKAGE__);

sub DEMOLISH ( $self, $global ) {
    if ( !$global && $self->{_response_status} != $HTTP_SERVER_RESPONSE_FINISHED ) {

        # request is destroyed without ->finish call, possible unhandled error in AE callback
        $self->return_xxx(500);
    }

    return;
}

sub _build__use_keepalive($self) {
    return 0 if !$self->{_server}->{keepalive_timeout};

    my $env = $self->{env};

    if ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.1' ) {
        return 0 if $env->{HTTP_CONNECTION} && $env->{HTTP_CONNECTION} =~ /\bclose\b/smi;
    }
    elsif ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.0' ) {
        return 0 if !$env->{HTTP_CONNECTION} || $env->{HTTP_CONNECTION} !~ /\bkeep-?alive\b/smi;
    }

    return 1;
}

sub body ($self) {
    return $self->{env}->{'psgi.input'} ? \$self->{env}->{'psgi.input'} : undef;
}

# TODO serialize body related to body ref type and content type
sub write ( $self, @ ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    die q[Unable to write, HTTP response is already finished] if $self->{_response_status} == $HTTP_SERVER_RESPONSE_FINISHED;

    my $body;

    if ( !$self->{_response_status} ) {

        # compose headers
        # https://tools.ietf.org/html/rfc7230#section-3.2
        my $headers = do {
            if ( !ref $_[1] ) {
                "HTTP/1.1 $_[1] " . Pcore::HTTP::Status->get_reason( $_[1] ) . $CRLF;
            }
            else {
                "HTTP/1.1 $_[1]->[0] $_[1]->[1]$CRLF";
            }
        };

        $headers .= "Server:$self->{_server}->{server_tokens}$CRLF" if $self->{server_tokens};

        # always use chunked transfer
        $headers .= "Transfer-Encoding:chunked$CRLF";

        # keepalive
        $headers .= 'Connection:' . ( $self->_use_keepalive ? 'keep-alive' : 'close' ) . $CRLF;

        # add custom headers
        $headers .= join( $CRLF, map {"$_->[0]:$_->[1]"} pairs $_[2]->@* ) . $CRLF if $_[2] && $_[2]->@*;

        $headers .= $CRLF;

        $self->{_h}->push_write($headers);

        \$body = \$_[3] if $_[3];

        $self->{_response_status} = $HTTP_SERVER_RESPONSE_STARTED;
    }
    else {
        \$body = \$_[1];
    }

    if ($body) {
        my $body_ref = ref $body;

        if ( !$body_ref ) {
            $self->{_h}->push_write( sprintf( '%x', bytes::length $body ) . $CRLF . encode_utf8($body) . $CRLF );
        }
        elsif ( $body_ref eq 'SCALAR' ) {
            $self->{_h}->push_write( sprintf( '%x', bytes::length $body->$* ) . $CRLF . encode_utf8( $body->$* ) . $CRLF );
        }
        elsif ( $body_ref eq 'ARRAY' ) {
            my $buf = join q[], map { encode_utf8 $_} $body->@*;

            $self->{_h}->push_write( sprintf( '%x', bytes::length $buf ) . $CRLF . $buf . $CRLF );
        }
        else {

            # TODO add support for other body types
            die q[Body type isn't supported];
        }
    }

    return $self;
}

sub finish ( $self, $trailing_headers = undef ) {
    my $response_status = $self->{_response_status};

    die q[Unable to finish already finished HTTP request] if $response_status == $HTTP_SERVER_RESPONSE_FINISHED;

    my $use_keepalive = $self->_use_keepalive;

    if ( !$response_status ) {

        # return 204 No Content - the server successfully processed the request and is not returning any content
        $self->return_xxx( 204, $use_keepalive );
    }
    else {
        # mark request as finished
        $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

        # write last chunk
        my $buf = "0$CRLF";

        # write trailing headers
        # https://tools.ietf.org/html/rfc7230#section-3.2
        $buf .= ( join $CRLF, map {"$_->[0]:$_->[1]"} pairs $trailing_headers->@* ) . $CRLF if $trailing_headers && $trailing_headers->@*;

        # close response
        $buf .= $CRLF;

        $self->{_h}->push_write($buf);

        # process handle
        if   ($use_keepalive) { $self->{_server}->wait_headers( $self->{_h} ) }
        else                  { $self->{_h}->destroy }

        undef $self->{_h};
    }

    return;
}

# return simple response and finish request
sub return_xxx ( $self, $status, $use_keepalive = 0 ) {
    die q[Unable to finish already started HTTP request] if $self->{_response_status};

    $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

    $self->{_server}->return_xxx( $self->{_h}, $status, $use_keepalive );

    undef $self->{_h};

    return;
}

sub accept_websocket ( $self, $headers = undef ) {
    state $reason = Pcore::HTTP::Status->get_reason(101);

    die q[Unable to finish already started HTTP request] if $self->{_response_status};

    $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

    my @headers = (    #
        "HTTP/1.1 $status $reason",
        'Content-Length:0',
        'Upgrade:websocket',
        'Connection:upgrade',
        ( $self->{server_tokens} ? "Server:$self->{server_tokens}" : () ),
    );

    push @headers, map {"$_->[0]:$_->[1]"} pairs $headers->@* if $headers && $headers->@*;

    $self->{_h}->push_write( join( $CRLF, @headers ) . $CRLF . $CRLF );

    return $h;
}

1;
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
