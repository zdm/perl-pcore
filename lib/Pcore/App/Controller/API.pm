package Pcore::App::Controller::API;

use Pcore -const, -role;
use Pcore::Util::Data qw[from_json to_json from_cbor to_cbor];
use Pcore::HTTP::Status;

with qw[Pcore::App::Controller::WebSocket];

# HTTP_AUTHORIZATION - Basic - username:password
# HTTP_AUTHORIZATION - Token - token
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

sub run ( $self, $req ) {
    my $env = $req->{env};

    my $content_type = $CONTENT_TYPE_JSON;

    my $request_id;

    # create callback
    my $cb = sub ( $status, $result = undef ) {
        my $reason;

        if ( ref $status eq 'ARRAY' ) {
            $reason = $status->[1];

            $status = $status->[0];
        }
        else {
            $reason = Pcore::HTTP::Status->get_reason($status);
        }

        # create list of HTTP response headers
        my @headers = (    #
            'Content-Type' => $content_type == $CONTENT_TYPE_JSON ? 'application/json' : 'application/cbor',
        );

        my $body = {
            status     => $status,
            reason     => $reason,
            request_id => $request_id,
            result     => $result,
        };

        # write HTTP response
        $req->write( [ $status, $reason ], \@headers, $content_type == $CONTENT_TYPE_JSON ? to_json $body : to_cbor $body)->finish;

        # free HTTP request object
        undef $req;

        return;
    };

    my $request;

    # JSON content type
    if ( !$env->{CONTENT_TYPE} || $env->{CONTENT_TYPE} =~ m[\bapplication/json\b]smi ) {
        $request = eval { from_json $req->body };

        # content decode error
        return $cb->( [ 400, q[Error decoding JSON request body] ] ) if $@;
    }

    # CBOR content type
    elsif ( $env->{CONTENT_TYPE} =~ m[\bapplication/cbor\b]smi ) {
        $content_type = $CONTENT_TYPE_CBOR;

        $request = eval { from_cbor $req->body };

        # content decode error
        return $cb->( [ 400, q[Error decoding CBOR request body] ] ) if $@;
    }

    # invalid content type
    else {
        return $cb->( [ 400, q[Content type is invalid] ] );
    }

    # set request id
    $request_id = $request->{request_id};

    # get auth token
    my $token = $self->_get_token($env);

    # no auth token provided
    return $cb->( [ 401, q[Authentication token wasn't provided] ] ) if !$token;

    # authenticate token
    $self->{app}->{api}->auth_token(
        $token,
        sub ($api_session) {

            # token authentication error
            return $cb->( [ 401, q[Unauthorized] ] ) if !$api_session;

            # detect method id
            my $method_id;

            # get metod id from request
            if ( $request->{method} ) {
                $method_id = $request->{method};
            }

            # get metod id from HTTP request path tail
            elsif ( $req->{path_tail} ) {
                $method_id = $req->{path_tail};
            }

            # method id wasn't found
            else {
                return $cb->( [ 400, q[Method is required] ] );
            }

            $api_session->api_call( $method_id, $request->{args}, $cb );

            return;
        }
    );

    return;
}

# TODO get username/password from basic authentication???
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
sub _websocket_call ( $self, $ws, $payload_ref, $content_type ) {

    # decode payload
    my $request = eval { $content_type eq $CONTENT_TYPE_JSON ? from_json $payload_ref : from_cbor $payload_ref};

    # content decode error
    return $self->websocket_disconnect( $ws, 400, q[Error decoding request body] ) if $@;

    my $token = $ws->{token};

    # authenticate token
    $self->{app}->{api}->auth_token(
        $token,
        sub ($api_session) {

            # token authentication error
            return $self->websocket_disconnect( $ws, 401, q[Unauthorized] ) if !$api_session;

            # detect method id
            my $method_id;

            # get method id from request
            if ( $request->{method} ) {
                $method_id = $request->{method};
            }

            # method id wasn't found
            else {
                return $self->websocket_disconnect( $ws, 400, q[Method is required] );
            }

            # create callback
            my $cb;

            if ( my $request_id = $request->{request_id} ) {
                $cb = sub ( $status, $result = undef ) {
                    my $reason;

                    if ( ref $status eq 'ARRAY' ) {
                        $reason = $status->[1];

                        $status = $status->[0];
                    }
                    else {
                        $reason = Pcore::HTTP::Status->get_reason($status);
                    }

                    my $body = {
                        status     => $status,
                        reason     => $reason,
                        request_id => $request_id,
                        result     => $result,
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

            $api_session->api_call( $method_id, $request->{args}, $cb );

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
        sub ($api_session) {

            # token authentication error
            return $decline->(401) if !$api_session;

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
    $self->_websocket_call( $ws, $payload_ref, $CONTENT_TYPE_JSON );

    return;
}

sub websocket_on_binary ( $self, $ws, $payload_ref ) {
    $self->_websocket_call( $ws, $payload_ref, $CONTENT_TYPE_CBOR );

    return;
}

sub websocket_on_pong ( $self, $ws, $payload ) {
    return;
}

sub websocket_on_disconnect ( $self, $ws, $status, $reason ) {
    say "DISCONNECTED: $status $reason";
    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 158                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
