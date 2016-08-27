package Pcore::App::Controller::API;

use Pcore -const, -role;
use Pcore::Util::Data qw[from_json to_json from_cbor to_cbor];
use Pcore::Util::Status;
use Pcore::Util::Scalar qw[blessed];

with qw[Pcore::App::Controller::WebSocket];

# HTTP_AUTHORIZATION - Basic - username:password
# HTTP_AUTHORIZATION - token - token
# QUERY_STRING = access_token=asdasd

const our $CONTENT_TYPE_JSON => 1;
const our $CONTENT_TYPE_CBOR => 2;

sub _build_websocket_subprotocol ($self) {
    return 'pcore-api';
}

sub _build_websocket_max_message_size ($self) {
    return 1024 * 1024 * 10;
}

sub _build_websocket_autopong ($self) {
    return 50;
}

# ENTRYPOINT
sub run ( $self, $req ) {
    my $env = $req->{env};

    my $content_type = $CONTENT_TYPE_JSON;

    my $cid;

    # create callback
    my $cb = sub ( $status, @args ) {
        $status = Pcore::Util::Status->new( { status => $status } ) if !blessed $status;

        # create list of HTTP response headers
        my @headers = (    #
            'Content-Type' => $content_type == $CONTENT_TYPE_JSON ? 'application/json' : 'application/cbor',
        );

        my $body = {
            cid    => $cid,
            status => $status,
            args   => @args ? \@args : undef,
        };

        # write HTTP response
        $req->( $status, \@headers, $content_type == $CONTENT_TYPE_JSON ? to_json $body : to_cbor $body)->finish;

        # free HTTP request object
        undef $req;

        return;
    };

    my $data;

    # JSON content type
    if ( !$env->{CONTENT_TYPE} || $env->{CONTENT_TYPE} =~ m[\bapplication/json\b]smi ) {
        $data = eval { from_json $req->body };

        # content decode error
        return $cb->( [ 400, q[Error decoding JSON request body] ] ) if $@;
    }

    # CBOR content type
    elsif ( $env->{CONTENT_TYPE} =~ m[\bapplication/cbor\b]smi ) {
        $content_type = $CONTENT_TYPE_CBOR;

        $data = eval { from_cbor $req->body };

        # content decode error
        return $cb->( [ 400, q[Error decoding CBOR request body] ] ) if $@;
    }

    # invalid content type
    else {
        return $cb->( [ 400, q[Content type is invalid] ] );
    }

    # set request id
    $cid = $data->{cid};

    # method is not specified, this is callback, not supported in API server
    return $cb->( [ 400, q[Method is required] ] ) if !$data->{method};

    # get auth token
    my $token = $self->_get_token($env);

    # no auth token provided
    return $cb->( [ 401, q[Authentication token wasn't provided] ] ) if !$token;

    # authenticate token
    $self->{app}->{api}->auth_token(
        $token,
        sub ($api_request) {

            # token authentication error
            return $cb->( [ 401, q[Unauthorized] ] ) if !$api_request;

            # method is specified, this is API call
            if ( my $method_id = $data->{method} ) {
                $api_request->api_call_arrayref( $method_id, $data->{args}, $cb );
            }

            # method is not specified, this is callback, not supported in API server
            else {
                return $cb->( [ 400, q[Method is required] ] );
            }

            return;
        }
    );

    return;
}

# parse and return token from HTTP request
sub _get_token ( $self, $env ) {

    # get auth token from query param, header, cookie
    my $token;

    if ( $env->{QUERY_STRING} && $env->{QUERY_STRING} =~ /\baccess_token=([^&]+)/sm ) {
        $token = $1;
    }
    elsif ( $env->{HTTP_AUTHORIZATION} && $env->{HTTP_AUTHORIZATION} =~ /Token\s+(.+)\b/smi ) {
        $token = $1;
    }
    elsif ( $env->{HTTP_COOKIE} && $env->{HTTP_COOKIE} =~ /\btoken=([^;]+)\b/sm ) {
        $token = $1;
    }

    return $token;
}

# WEBSOCKET INTERFACE
sub _websocket_api_call ( $self, $ws, $payload_ref, $content_type ) {

    # decode payload
    my $data = eval { $content_type eq $CONTENT_TYPE_JSON ? from_json $payload_ref : from_cbor $payload_ref};

    # content decode error
    return $self->websocket_disconnect( $ws, 400, q[Error decoding request body] ) if $@;

    my $token = $ws->{token};

    # authenticate token
    $self->{app}->{api}->auth_token(
        $token,
        sub ($api_request) {

            # token authentication error
            return $self->websocket_disconnect( $ws, 401, q[Unauthorized] ) if !$api_request;

            # method is specified, this is API call
            if ( my $method_id = $data->{method} ) {
                my $cb;

                # this is not void API call, create callback
                if ( my $cid = $data->{cid} ) {
                    $cb = sub ( $status, @args ) {
                        my $body = {
                            cid    => $cid,
                            status => $status,
                            args   => @args ? \@args : undef,
                        };

                        # write response
                        if ( $content_type eq $CONTENT_TYPE_JSON ) {
                            $ws->send_text( to_json($body)->$* );
                        }
                        else {
                            $ws->send_binary( to_cbor($body)->$* );
                        }

                        return;
                    };
                }

                $api_request->api_call_arrayref( $method_id, $data->{args}, $cb );
            }

            # method is not specified, this is callback, not supported in API server
            else {
                return $self->websocket_disconnect( $ws, 400, q[Method is required] );
            }

            return;
        }
    );

    return;
}

sub websocket_on_accept ( $self, $ws, $req, $accept, $decline ) {
    my $token = $self->_get_token( $req->{env} );

    # no auth token provided
    return $decline->(401) if !$token;

    $self->{app}->{api}->auth_token(
        $token,
        sub ($api_request) {

            # token authentication error
            return $decline->(401) if !$api_request;

            # token authenticated successfully, store token in websocket connection object
            $ws->{token} = $token;

            # accept websocket connection
            $accept->();

            return;
        }
    );

    return;
}

sub websocket_on_connect ( $self, $ws ) {
    return;
}

sub websocket_on_text ( $self, $ws, $payload_ref ) {
    $self->_websocket_api_call( $ws, $payload_ref, $CONTENT_TYPE_JSON );

    return;
}

sub websocket_on_binary ( $self, $ws, $payload_ref ) {
    $self->_websocket_api_call( $ws, $payload_ref, $CONTENT_TYPE_CBOR );

    return;
}

sub websocket_on_pong ( $self, $ws, $payload ) {
    return;
}

sub websocket_on_disconnect ( $self, $ws, $status, $reason ) {
    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 143                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::Controller::API

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
