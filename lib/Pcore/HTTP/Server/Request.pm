package Pcore::HTTP::Server::Request;

use Pcore -class, -const, -res;
use Pcore::Util::Scalar qw[is_ref is_plain_scalarref is_plain_arrayref];
use Pcore::Util::List qw[pairs];
use Pcore::Util::Text qw[encode_utf8];
use Pcore::App::API::Auth;

use overload    #
  q[&{}] => sub ( $self, @ ) {
    return sub { return _respond( $self, @_ ) };
  },
  fallback => undef;

has _server   => ();    # ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server'], required => 1 );
has _h        => ();    # ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'],   required => 1 );
has env       => ();    # ( is => 'ro', isa => HashRef, required => 1 );
has data      => ();
has keepalive => ();

has is_websocket_connect_request => ( is => 'lazy' );    # ( is => 'lazy', isa => Bool, init_arg => undef );

has _response_status => 0;                               # ( is => 'ro', isa => Bool, default => 0, init_arg => undef );
has _auth            => ();                              # ( is => 'ro', isa => Object, init_arg => undef );    # request authentication result

const our $HTTP_SERVER_RESPONSE_STARTED  => 1;           # headers written
const our $HTTP_SERVER_RESPONSE_FINISHED => 2;           # body written

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

sub DESTROY ( $self ) {

    # request is destroyed without ->finish call
    if ( ( ${^GLOBAL_PHASE} ne 'DESTRUCT' ) && $self->{_response_status} != $HTTP_SERVER_RESPONSE_FINISHED ) {

        # HTTP headers is not written
        if ( !$self->{_response_status} ) {
            $self->return_xxx( 500, 1 );
        }
        else {
            $self->{_cb}->(1);
        }
    }

    return;
}

# TODO serialize body related to body ref type and content type
sub _respond ( $self, @ ) {
    die q[Unable to write, HTTP response is already finished] if $self->{_response_status} == $HTTP_SERVER_RESPONSE_FINISHED;

    my ( $buf, $body );

    # first call, $status, $headers, $body
    if ( !$self->{_response_status} ) {

        # compose headers
        # https://tools.ietf.org/html/rfc7230#section-3.2
        $buf = do {
            my $status = 0+ $_[1];
            my $reason = Pcore::Util::Result::get_standard_reason($status);

            "HTTP/1.1 $status $reason\r\n";
        };

        $buf .= "Server:$self->{_server}->{server_tokens}\r\n" if $self->{_server}->{server_tokens};

        # always use chunked transfer
        $buf .= "Transfer-Encoding:chunked\r\n";

        # keepalive
        $buf .= 'Connection:' . ( $self->{keepalive} ? 'keep-alive' : 'close' ) . $CRLF;

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
        if ( !is_ref $body ) {
            $buf .= sprintf "%x$CRLF%s$CRLF", bytes::length $body, encode_utf8 $body;
        }
        elsif ( is_plain_scalarref $body ) {
            $buf .= sprintf "%x$CRLF%s$CRLF", bytes::length $body->$*, encode_utf8 $body->$*;
        }
        elsif ( is_plain_arrayref $body ) {
            my $buf1 = join q[], map { encode_utf8 $_} $body->@*;

            $buf .= sprintf "%x$CRLF%s$CRLF", bytes::length $buf1, $buf1;
        }
        else {

            # TODO add support for other body types
            die q[Body type isn't supported];
        }
    }

    $self->{_h}->write($buf);

    return $self;
}

sub finish ( $self, $trailing_headers = undef ) {
    my $response_status = $self->{_response_status};

    die q[Unable to finish already finished HTTP request] if $response_status == $HTTP_SERVER_RESPONSE_FINISHED;

    # HTTP headers are not written
    if ( !$response_status ) {

        # return 204 No Content - the server successfully processed the request and is not returning any content
        $self->return_xxx(204);
    }

    # HTTP headers are written
    else {

        # mark request as finished
        $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

        # write last chunk
        my $buf = "0\r\n";

        # write trailing headers
        # https://tools.ietf.org/html/rfc7230#section-3.2
        $buf .= ( join $CRLF, map {"$_->[0]:$_->[1]"} pairs $trailing_headers->@* ) . $CRLF if $trailing_headers && $trailing_headers->@*;

        # close response
        $buf .= $CRLF;

        $self->{_h}->write($buf);

        $self->{_cb}->(0);
    }

    return;
}

# return simple response and finish request
sub return_xxx ( $self, $status, $close_connection = 0 ) {
    die q[Unable to finish already started HTTP request] if $self->{_response_status};

    # mark request as finished
    $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

    $self->{_server}->return_xxx( $self->{_h}, $status, $close_connection || !$self->{keepalive} );

    $self->{_cb}->($close_connection);

    return;
}

# WEBSOCKET
sub _build_is_websocket_connect_request ( $self ) {
    my $env = $self->{env};

    return $env->{HTTP_UPGRADE} && $env->{HTTP_UPGRADE} =~ /websocket/smi && $env->{HTTP_CONNECTION} && $env->{HTTP_CONNECTION} =~ /\bupgrade\b/smi;
}

sub accept_websocket ( $self, $headers = undef ) {
    state $reason = 'Switching Protocols';

    die q[Unable to finish already started HTTP request] if $self->{_response_status};

    # mark response as finished
    $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

    my $buf = "HTTP/1.1 101 $reason\r\nContent-Length:0\r\nUpgrade:websocket\r\nConnection:upgrade\r\n";

    $buf .= "Server:$self->{_server}->{server_tokens}\r\n" if $self->{_server}->{server_tokens};

    $buf .= ( join $CRLF, map {"$_->[0]:$_->[1]"} pairs $headers->@* ) . $CRLF if $headers && $headers->@*;

    my $h = delete $self->{_h};

    $h->write( $buf . $CRLF );

    $self->{_cb}->(1);

    return $h;
}

# AUTHENTICATE
sub authenticate ( $self ) {

    # request is already authenticated
    if ( exists $self->{_auth} ) {
        return $self->{_auth};
    }
    elsif ( !$self->{app}->{api} ) {
        return $self->{_auth} = bless { app => $self->{app} }, 'Pcore::App::API::Auth';
    }
    else {
        my $env = $self->{env};

        # get auth token from query param, header, cookie
        my $token;

        if ( $env->{QUERY_STRING} && $env->{QUERY_STRING} =~ /\baccess_token=([^&]+)/sm ) {
            $token = $1;
        }
        elsif ( $env->{HTTP_AUTHORIZATION} && $env->{HTTP_AUTHORIZATION} =~ /Token\s+(.+)\b/smi ) {
            $token = $1;
        }
        elsif ( $env->{HTTP_AUTHORIZATION} && $env->{HTTP_AUTHORIZATION} =~ /Basic\s+(.+)\b/smi ) {
            $token = eval { from_b64 $1};

            $token = [ split /:/sm, $token ] if $token;

            undef $token if !defined $token->[0];
        }
        elsif ( $env->{HTTP_COOKIE} && $env->{HTTP_COOKIE} =~ /\btoken=([^;]+)\b/sm ) {
            $token = $1;
        }

        return $self->{_auth} = $self->{app}->{api}->authenticate($token);
    }
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
