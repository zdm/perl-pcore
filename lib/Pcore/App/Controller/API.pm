package Pcore::App::Controller::API;

use Pcore -const, -role, -status;
use Pcore::Util::Data qw[from_json to_json from_cbor to_cbor];

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
    my $cb = sub ( $status ) {
        $status->{cid} = $cid;

        # create list of HTTP response headers
        my @headers = (    #
            'Content-Type' => $content_type == $CONTENT_TYPE_JSON ? 'application/json' : 'application/cbor',
        );

        # write HTTP response
        $req->( $status, \@headers, $content_type == $CONTENT_TYPE_JSON ? to_json $status : to_cbor $status)->finish;

        # free HTTP request object
        undef $req;

        return;
    };

    my $data;

    # JSON content type
    if ( !$env->{CONTENT_TYPE} || $env->{CONTENT_TYPE} =~ m[\bapplication/json\b]smi ) {
        $data = eval { from_json $req->body };

        # content decode error
        return $cb->( status [ 400, q[Error decoding JSON request body] ] ) if $@;
    }

    # CBOR content type
    elsif ( $env->{CONTENT_TYPE} =~ m[\bapplication/cbor\b]smi ) {
        $content_type = $CONTENT_TYPE_CBOR;

        $data = eval { from_cbor $req->body };

        # content decode error
        return $cb->( status [ 400, q[Error decoding CBOR request body] ] ) if $@;
    }

    # invalid content type
    else {
        return $cb->( status [ 400, q[Content type is invalid] ] );
    }

    # set request id
    $cid = $data->{cid};

    # method is not specified, this is callback, not supported in API server
    return $cb->( status [ 400, q[Method is required] ] ) if !$data->{method};

    # authenticate request
    $req->authenticate(
        sub ( $auth ) {

            # token authentication error
            if ( !$auth ) {
                $cb->($auth);

                return;
            }

            # this is app connection, disabled
            if ( $auth->{is_app} ) {
                $cb->( status [ 403, q[App must connect via WebSocket interface] ] );
            }

            # method is specified, this is API call
            elsif ( my $method_id = $data->{method} ) {
                $auth->api_call_arrayref( $method_id, $data->{args}, $cb );
            }

            # method is not specified, this is callback, not supported in API server
            else {
                $cb->( status [ 400, q[Method is required] ] );
            }

            return;
        }
    );

    return;
}

# WEBSOCKET INTERFACE
sub _websocket_api_call ( $self, $ws, $payload_ref, $content_type ) {

    # decode payload
    my $data = eval { $content_type eq $CONTENT_TYPE_JSON ? from_json $payload_ref : from_cbor $payload_ref};

    # content decode error
    return $self->websocket_disconnect( $ws, 400, q[Error decoding request body] ) if $@;

    my $auth = $ws->{auth};

    # method is specified, this is API call
    if ( my $method_id = $data->{method} ) {
        my $cb;

        # this is not void API call, create callback
        if ( my $cid = $data->{cid} ) {
            $cb = sub ( $status ) {
                $status->{cid} = $cid;

                # write response
                if ( $content_type eq $CONTENT_TYPE_JSON ) {
                    $ws->send_text( to_json($status)->$* );
                }
                else {
                    $ws->send_binary( to_cbor($status)->$* );
                }

                return;
            };
        }

        $auth->api_call_arrayref( $method_id, $data->{args}, $cb );
    }

    # method is not specified, this is callback, not supported in API server
    else {
        return $self->websocket_disconnect( $ws, 400, q[Method is required] );
    }

    return;
}

sub websocket_on_accept ( $self, $ws, $req, $accept, $decline ) {

    # authenticate request
    $req->authenticate(
        sub ( $auth ) {

            # token authentication error
            if ( !$auth ) {
                $decline->($auth);
            }
            else {

                # token authenticated successfully, store token in websocket connection object
                $ws->{auth} = $auth;

                # accept websocket connection
                $accept->();
            }

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
## |    3 | 118                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
