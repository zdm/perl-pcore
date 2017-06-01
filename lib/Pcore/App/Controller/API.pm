package Pcore::App::Controller::API;

use Pcore -role, -result, -const;
use Pcore::Util::Data qw[from_json to_json from_cbor to_cbor from_uri_query];
use Pcore::WebSocket;

with qw[Pcore::App::Controller];

const our $WS_MAX_MESSAGE_SIZE => 1_024 * 1_024 * 100;    # 100 Mb
const our $WS_PONG_INTERVAL    => 50;
const our $WS_COMPRESSION      => 0;

const our $TX_TYPE_RPC       => 'rpc';
const our $TX_TYPE_EXCEPTION => 'exception';

sub run ( $self, $req ) {
    if ( $req->{path_tail} ) {
        $req->(404)->finish;

        return;
    }

    # WebSocket API request
    if ( $req->is_websocket_connect_request ) {
        Pcore::WebSocket->accept_ws(
            'pcore', $req,
            sub ( $req, $accept, $reject ) {

                # authenticate request
                $req->authenticate(
                    sub ( $auth ) {

                        # accept websocket connection
                        $accept->(
                            max_message_size => $WS_MAX_MESSAGE_SIZE,
                            pong_interval    => $WS_PONG_INTERVAL,
                            compression      => $WS_COMPRESSION,
                            on_listen_event  => sub ( $ws, $mask ) {
                                return $self->on_listen_event( $ws, $mask );
                            },
                            on_fire_event => sub ( $ws, $ev ) {
                                return $self->on_fire_event( $ws, $ev );
                            },
                            before_connect => undef,
                            on_connect     => sub ($ws) {

                                # store auth in websocket connection object
                                $ws->{auth} = $auth;

                                $self->on_connect($ws);

                                return;
                            },
                            on_disconnect => undef,
                            on_rpc        => sub ( $ws, $req, $tx ) {
                                $ws->{auth}->api_call_arrayref( $tx->{method}, $tx->{data}, $req );

                                return;
                            },
                        );

                        return;
                    }
                );

                return;
            },
        );
    }

    # HTTP API request
    else {
        my $env = $req->{env};

        my $msg;

        my $CBOR = 0;

        # decode API request
        if ( !$env->{CONTENT_TYPE} || $env->{CONTENT_TYPE} =~ m[\bapplication/json\b]smi ) {
            $msg = eval { from_json $req->body };

            # content decode error
            if ($@) {
                $req->( [ 400, q[Error decoding JSON request body] ] )->finish;

                return;
            }
        }

        elsif ( $env->{CONTENT_TYPE} =~ m[\bapplication/cbor\b]smi ) {
            $msg = eval { from_cbor $req->body };

            # content decode error
            if ($@) {
                $req->( [ 400, q[Error decoding JSON request body] ] )->finish;

                return;
            }

            $CBOR = 1;
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
                    $self->_http_api_router(
                        $auth, $msg,
                        sub ($res) {
                            if ($CBOR) {

                                # write HTTP response
                                $req->( 200, [ 'Content-Type' => 'application/cbor' ], to_cbor $res )->finish;
                            }
                            else {

                                # write HTTP response
                                $req->( 200, [ 'Content-Type' => 'application/json' ], to_json $res)->finish;
                            }

                            # free HTTP request object
                            undef $req;

                            return;
                        }
                    );
                }

                return;
            }
        );
    }

    return;
}

sub _http_api_router ( $self, $auth, $data, $cb ) {
    $data = [$data] if ref $data ne 'ARRAY';

    my $response;

    my $cv = AE::cv sub {
        $cb->($response);

        return;
    };

    $cv->begin;

    for my $tx ( $data->@* ) {

        # TODO required only for compatibility with old clients, can be removed
        $tx->{type} ||= $TX_TYPE_RPC;

        # check message type, only rpc calls are enabled here
        if ( $tx->{type} ne $TX_TYPE_RPC ) {
            push $response->@*,
              { tid     => $tx->{tid},
                type    => $TX_TYPE_EXCEPTION,
                message => {
                    status => 400,
                    reason => 'Invalid API request type',
                },
              };

            next;
        }

        # method is not specified, this is callback, not supported in API server
        if ( !$tx->{method} ) {
            push $response->@*,
              { tid     => $tx->{tid},
                type    => $TX_TYPE_EXCEPTION,
                message => {
                    status => 400,
                    reason => 'Method is required',
                },
              };

            next;
        }

        $cv->begin;

        # combine method with action
        if ( my $action = delete $tx->{action} ) {
            $tx->{method} = q[/] . ( $action =~ s[[.]][/]smgr ) . "/$tx->{method}";
        }

        $auth->api_call_arrayref(
            $tx->{method},
            $tx->{data},
            sub ($res) {
                if ( $res->is_success ) {
                    push $response->@*,
                      { type   => $TX_TYPE_RPC,
                        tid    => $tx->{tid},
                        result => $res,
                      };
                }
                else {
                    push $response->@*,
                      { type    => $TX_TYPE_EXCEPTION,
                        tid     => $tx->{tid},
                        message => $res,
                      };
                }

                $cv->end;

                return;
            }
        );
    }

    $cv->end;

    return;
}

sub on_connect ( $self, $ws ) {
    return;
}

sub on_listen_event ( $self, $ws, $mask ) {
    return;
}

sub on_fire_event ( $self, $ws, $ev ) {
    return;
}

1;
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
