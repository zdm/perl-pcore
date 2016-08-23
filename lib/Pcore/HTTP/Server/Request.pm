package Pcore::HTTP::Server::Request;

use Pcore -class, -const;
use Pcore::Util::Status;
use Pcore::Util::Scalar qw[blessed];
use Pcore::Util::List qw[pairs];
use Pcore::Util::Text qw[encode_utf8];

use overload    #
  q[&{}] => sub ( $self, @ ) {
    use subs qw[write];

    return sub { return write( $self, @_ ) };
  },
  fallback => undef;

has _server => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server'], required => 1 );
has _h      => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'],   required => 1 );
has env => ( is => 'ro', isa => HashRef, required => 1 );

has is_websocket_connect_request => ( is => 'lazy', isa => Bool, init_arg => undef );
has _use_keepalive               => ( is => 'lazy', isa => Bool, init_arg => undef );

has _response_status => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

const our $HTTP_SERVER_RESPONSE_STARTED  => 1;    # headers written
const our $HTTP_SERVER_RESPONSE_FINISHED => 2;    # body written

# const our $CONTENT_TYPE_HTML       => 1;
# const our $CONTENT_TYPE_TEXT       => 2;
# const our $CONTENT_TYPE_JSON       => 3;
# const our $CONTENT_TYPE_CBOR       => 4;
# const our $CONTENT_TYPE_JAVASCRIPT => 5;
#
# const our $CONTENT_TYPE_VALUE => {
#     $CONTENT_TYPE_JSON       => 'application/json',                           # http://www.iana.org/assignments/media-types/application/json
#     $CONTENT_TYPE_CBOR       => 'application/cbor',                           # http://www.iana.org/assignments/media-types/application/cbor
#     $CONTENT_TYPE_JAVASCRIPT => 'application/javascript; charset=UTF-8',      # http://www.iana.org/assignments/media-types/application/javascript
#     $CONTENT_TYPE_XML        => 'application/xml',
#     $CONTENT_TYPE_HTML       => 'text/html; charset=UTF-8',                   # http://www.iana.org/assignments/media-types/text/html
#     $CONTENT_TYPE_TEXT       => 'text/plain; charset=UTF-8',
#     $CONTENT_TYPE_CSS        => 'text/css; charset=UTF-8',                    # http://www.iana.org/assignments/media-types/text/css
#     $CONTENT_TYPE_CSV        => 'text/csv; charset=UTF-8; header=present',    # http://www.iana.org/assignments/media-types/text/csv
# };

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

    my ( $buf, $body );

    if ( !$self->{_response_status} ) {

        # compose headers
        # https://tools.ietf.org/html/rfc7230#section-3.2
        $buf = do {
            my $status = blessed $_[1] ? $_[1] : Pcore::Util::Status->new( { status => $_[1] } );

            "HTTP/1.1 $status->{status} $status->{reason}$CRLF";
        };

        $buf .= "Server:$self->{_server}->{server_tokens}$CRLF" if $self->{_server}->{server_tokens};

        # always use chunked transfer
        $buf .= "Transfer-Encoding:chunked$CRLF";

        # keepalive
        $buf .= 'Connection:' . ( $self->_use_keepalive ? 'keep-alive' : 'close' ) . $CRLF;

        # add custom headers
        $buf .= join( $CRLF, map {"$_->[0]:$_->[1]"} pairs $_[2]->@* ) . $CRLF if $_[2] && $_[2]->@*;

        $buf .= $CRLF;

        \$body = \$_[3] if $_[3];

        $self->{_response_status} = $HTTP_SERVER_RESPONSE_STARTED;
    }
    else {
        \$body = \$_[1];
    }

    if ($body) {
        my $body_ref = ref $body;

        if ( !$body_ref ) {
            $buf .= sprintf( '%x', bytes::length $body ) . $CRLF . encode_utf8($body) . $CRLF;
        }
        elsif ( $body_ref eq 'SCALAR' ) {
            $buf .= sprintf( '%x', bytes::length $body->$* ) . $CRLF . encode_utf8( $body->$* ) . $CRLF;
        }
        elsif ( $body_ref eq 'ARRAY' ) {
            my $buf1 = join q[], map { encode_utf8 $_} $body->@*;

            $buf .= sprintf( '%x', bytes::length $buf1 ) . $CRLF . $buf1 . $CRLF;
        }
        else {

            # TODO add support for other body types
            die q[Body type isn't supported];
        }
    }

    # TODO this call can be removed after issue in AnyEvent::Handle, lines 1021 and 1024, will be fixed
    utf8::downgrade $buf;

    $self->{_h}->push_write($buf);

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

# WEBSOCKET
sub _build_is_websocket_connect_request ( $self ) {
    my $env = $self->{env};

    return $env->{HTTP_UPGRADE} && $env->{HTTP_UPGRADE} =~ /websocket/smi && $env->{HTTP_CONNECTION} && $env->{HTTP_CONNECTION} =~ /\bupgrade\b/smi;
}

sub accept_websocket ( $self, $headers = undef ) {
    state $reason = Pcore::Util::Status->get_reason(101);

    die q[Unable to finish already started HTTP request] if $self->{_response_status};

    $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

    my $buf = "HTTP/1.1 101 $reason\r\nContent-Length:0\r\nUpgrade:websocket\r\nConnection:upgrade\r\n";

    $buf .= "Server:$self->{_server}->{server_tokens}\r\n" if $self->{_server}->{server_tokens};

    $buf .= ( join $CRLF, map {"$_->[0]:$_->[1]"} pairs $headers->@* ) . $CRLF if $headers && $headers->@*;

    my $h = $self->{_h};

    undef $self->{_h};

    $h->push_write( $buf . $CRLF );

    return $h;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    1 | 13                   | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
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
