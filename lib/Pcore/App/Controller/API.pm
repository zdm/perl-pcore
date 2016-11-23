package Pcore::App::Controller::API;

use Pcore -const, -role, -result;
use Pcore::Util::Data qw[from_json to_json from_cbor to_cbor from_uri_query];

with qw[Pcore::App::Controller::WebSocket];

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

    # ExtDirect API map
    if ( $req->{path_tail} ) {
        if ( $req->{path_tail} =~ m[\Aextdirect[.]json\z]sm ) {
            my $query = from_uri_query $req->{env}->{QUERY_STRING};

            my $ver = $query->{v};

            $req->authenticate(
                sub ( $auth ) {
                    $auth->extdirect_map(
                        $ver,
                        sub ($map) {
                            $req->( 200, [ 'Content-Type' => 'application/json' ], to_json $map, readable => 1 )->finish;

                            return;
                        }
                    );
                }
            );
        }
        else {
            $req->(404)->finish;
        }

        return;
    }

    my $env = $req->{env};

    my $content_type = $CONTENT_TYPE_JSON;

    my $data;

    # JSON content type
    if ( !$env->{CONTENT_TYPE} || $env->{CONTENT_TYPE} =~ m[\bapplication/json\b]smi ) {
        $data = eval { from_json $req->body };

        # content decode error
        if ($@) {
            $req->( [ 400, q[Error decoding JSON request body] ] )->finish;

            return;
        }
    }

    # CBOR content type
    elsif ( $env->{CONTENT_TYPE} =~ m[\bapplication/cbor\b]smi ) {
        $content_type = $CONTENT_TYPE_CBOR;

        $data = eval { from_cbor $req->body };

        if ($@) {
            $req->( [ 400, q[Error decoding CBOR request body] ] )->finish;

            return;
        }
    }

    # invalid content type
    else {
        $req->(415)->finish;

        return;
    }

    # authenticate request
    $req->authenticate(
        sub ( $auth ) {

            # this is app connection, disabled
            if ( $auth->{is_app} ) {
                $req->( [ 403, q[App must connect via WebSocket interface] ] )->finish;
            }
            else {
                $data = [$data] if ref $data ne 'ARRAY';

                my ( $response, @headers );

                my $cv = AE::cv sub {

                    # add Content-Type header
                    push @headers, ( 'Content-Type' => $content_type == $CONTENT_TYPE_JSON ? 'application/json' : 'application/cbor' );

                    # write HTTP response
                    $req->( 200, \@headers, $content_type == $CONTENT_TYPE_JSON ? to_json $response : to_cbor $response)->finish;

                    # free HTTP request object
                    undef $req;

                    return;
                };

                $cv->begin;

                for my $tx ( $data->@* ) {

                    # method is not specified, this is callback, not supported in API server
                    if ( !$tx->{method} ) {
                        push $response->@*,
                          { tid     => $tx->{tid},
                            type    => 'exception',
                            message => 'Method is required',
                          };

                        next;
                    }

                    $cv->begin;

                    # combine method with action
                    my $method_id = $tx->{action} ? q[/] . ( $tx->{action} =~ s[[.]][/]smgr ) . "/$tx->{method}" : $tx->{method};

                    $auth->api_call_arrayref(
                        $method_id,
                        [ $tx->{data} ],
                        sub ($res) {
                            if ( $res->is_success ) {
                                push $response->@*,
                                  { tid    => $tx->{tid},
                                    type   => 'rpc',
                                    result => $res,
                                  };

                                push @headers, $res->{headers}->@* if $res->{headers};
                            }
                            else {
                                push $response->@*,
                                  { tid     => $tx->{tid},
                                    type    => 'exception',
                                    message => $res->{message} // $res->{reason},
                                  };
                            }

                            $cv->end;

                            return;
                        }
                    );
                }

                $cv->end;
            }

            return;
        }
    );

    return;
}

# WEBSOCKET INTERFACE
# TODO make ExtDirect compatible
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
        if ( my $tid = $data->{tid} ) {
            $cb = sub ( $res ) {
                $res->{tid} = $tid;

                # write response
                if ( $content_type eq $CONTENT_TYPE_JSON ) {
                    $ws->send_text( to_json($res)->$* );
                }
                else {
                    $ws->send_binary( to_cbor($res)->$* );
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
## |    3 | 24                   | Subroutines::ProhibitExcessComplexity - Subroutine "run" with high complexity score (21)                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 178                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
