package Pcore::HTTP::Server::Request;

use Pcore -class, -const;
use Pcore::HTTP::Status;
use Pcore::Util::List qw[pairs];
use Pcore::Util::Text qw[encode_utf8];
use Digest::SHA1 qw[];

has _server => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server'], required => 1 );
has _h      => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'],   required => 1 );
has env => ( is => 'ro', isa => HashRef, required => 1 );

has _keepalive_timeout => ( is => 'lazy', isa => PositiveOrZeroInt, init_arg => undef );

has _response_status => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

const our $HTTP_SERVER_RESPONSE_STARTED  => 1;    # headers written
const our $HTTP_SERVER_RESPONSE_FINISHED => 2;    # body written

const our $WS_GUID => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

P->init_demolish(__PACKAGE__);

sub DEMOLISH ( $self, $global ) {
    if ( !$global && $self->{_response_status} != $HTTP_SERVER_RESPONSE_FINISHED ) {

        # request is destroyed without ->finish call, possible unhandled error in AE callback
        $self->{_server}->return_xxx( $self->{_h}, 500 );
    }

    return;
}

sub _build__keepalive_timeout($self) {
    my $keepalive_timeout = $self->{_server}->{keepalive_timeout};

    if ($keepalive_timeout) {
        my $env = $self->{env};

        if ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.1' ) {
            $keepalive_timeout = 0 if $env->{HTTP_CONNECTION} && $env->{HTTP_CONNECTION} =~ /\bclose\b/smi;
        }
        elsif ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.0' ) {
            $keepalive_timeout = 0 if !$env->{HTTP_CONNECTION} || $env->{HTTP_CONNECTION} !~ /\bkeep-?alive\b/smi;
        }
        else {
            $keepalive_timeout = 0;
        }
    }

    return $keepalive_timeout;
}

sub body ($self) {
    return $self->{env}->{'psgi.input'} ? \$self->{env}->{'psgi.input'} : undef;
}

# TODO convert headers to Camel-Case
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

        if ( $self->_keepalive_timeout ) {
            $headers .= "Connection:keep-alive$CRLF";
        }
        else {
            $headers .= "Connection:close$CRLF";
        }

        # TODO convert headers to Camel-Case
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

    if ( $response_status == $HTTP_SERVER_RESPONSE_FINISHED ) {
        die q[Unable to finish HTTP response, already finished];
    }
    else {

        # mark request as finished
        $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

        my $keepalive_timeout = $self->_keepalive_timeout;

        my $use_keepalive = !!$keepalive_timeout;

        if ( !$response_status ) {

            # return 204 No Content - The server successfully processed the request and is not returning any content
            $self->{_server}->return_xxx( $self->{_h}, 204, $use_keepalive );
        }
        else {

            # write last chunk
            my $buf = "0$CRLF";

            # write trailing headers
            # https://tools.ietf.org/html/rfc7230#section-3.2
            $buf .= ( join $CRLF, map {"$_->[0]:$_->[1]"} pairs $trailing_headers->@* ) . $CRLF if $trailing_headers && $trailing_headers->@*;

            # close response
            $buf .= $CRLF;

            $self->{_h}->push_write($buf);
        }

        if ($use_keepalive) {

            # keepalive
            $self->{_server}->wait_headers( $self->{_h} );

        }
        else {
            $self->{_h}->destroy;
        }

        undef $self->{_h};
    }

    return;
}

sub accept_websocket ($self) {

    # HTTP_SEC_WEBSOCKET_EXTENSIONS => "permessage-deflate"

    # HTTP_SEC_WEBSOCKET_VERSION => 13 handshake

    state $header = do {
        my $reason = Pcore::HTTP::Status->get_reason(101);

        my @headers = (    #
            "HTTP/1.1 101 $reason",
            'Content-Length:0',
            'Upgrade:WebSocket',
            'Connection:upgrade',
            ( $self->{server_tokens} ? "Server:$self->{server_tokens}" : () ),
        );

        join( $CRLF, @headers ) . $CRLF;
    };

    my $buf = $header;

    $buf .= 'Sec-WebSocket-Accept:' . P->data->to_b64( Digest::SHA1::sha1( ( $self->env->{HTTP_SEC_WEBSOCKET_KEY} || q[] ) . $WS_GUID ), q[] ) . $CRLF;

    # ' WebSocket-Origin '     => ' http : // 127.0.0.1 : 80 / ',
    # ' WebSocket-Location '   => ' ws   : // 127.0.0.1 : 80 / websocket /',

    $buf .= $CRLF;

    $self->{_h}->push_write($buf);

    $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

    return $self->_h;
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
