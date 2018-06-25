package Pcore::App::Controller::API;

use Pcore -role, -const;
use Pcore::Util::Data qw[from_json to_json from_cbor to_cbor from_uri_query];
use Pcore::Util::Scalar qw[is_plain_arrayref];
use Pcore::WebSocket::pcore;

with qw[Pcore::App::Controller];

const our $WS_MAX_MESSAGE_SIZE => 1_024 * 1_024 * 100;    # 100 Mb
const our $WS_COMPRESSION      => 0;

const our $TX_TYPE_RPC => 'rpc';

sub run ( $self, $req ) {
    if ( $req->{path_tail} ) {
        $req->(404)->finish;

        return;
    }

    # WebSocket API request
    if ( $req->is_websocket_connect_request ) {

        # create connection and accept websocket connect request
        Pcore::WebSocket::pcore->new(
            max_message_size => $WS_MAX_MESSAGE_SIZE,
            compression      => $WS_COMPRESSION,
            on_auth          => sub ( $h, $token, $cb ) {
                my $auth = $self->{app}->{api}->authenticate($token);

                $cb->($auth);

                return;
            },
            on_subscribe => sub ( $h, $event ) {
                return $self->on_subscribe_event( $h, $event );
            },
            on_event => sub ( $h, $ev ) {
                return $self->on_event( $h, $ev );
            },
            on_rpc => sub ( $h, $req, $tx ) {
                $h->{auth}->api_call_arrayref( $tx->{method}, $tx->{args}, $req );

                return;
            }
        )->accept($req);
    }

    # HTTP API request
    else {
        my $env = $req->{env};

        my $msg;

        my $CBOR = 0;

        # decode API request
        if ( !$env->{CONTENT_TYPE} || $env->{CONTENT_TYPE} =~ m[\bapplication/json\b]smi ) {
            $msg = eval { from_json $req->{body} };

            # content decode error
            if ($@) {
                $req->( [ 400, q[Error decoding JSON request body] ] )->finish;

                return;
            }
        }

        elsif ( $env->{CONTENT_TYPE} =~ m[\bapplication/cbor\b]smi ) {
            $msg = eval { from_cbor $req->{body} };

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
        my $auth = $req->authenticate;

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

                return;
            }
        );

        return;
    }

    return;
}

sub _http_api_router ( $self, $auth, $data, $cb ) {
    my $response;

    my $cv = AE::cv sub {
        $cb->($response);

        return;
    };

    $cv->begin;

    for my $tx ( is_plain_arrayref $data ? $data->@* : $data ) {
        next if !$tx->{type};

        # check message type, only rpc calls are enabled here
        if ( $tx->{type} eq $TX_TYPE_RPC ) {

            # method is not specified, this is callback, not supported in HTTP API server
            if ( !$tx->{method} ) {
                push $response->@*,
                  { type   => $TX_TYPE_RPC,
                    tid    => $tx->{tid},
                    result => {
                        status => 400,
                        reason => 'Method is required',
                    },
                  };

                next;
            }

            $cv->begin;

            $auth->api_call_arrayref(
                $tx->{method},
                $tx->{args},
                sub ($res) {
                    push $response->@*,
                      { type   => $TX_TYPE_RPC,
                        tid    => $tx->{tid},
                        result => $res,
                      };

                    $cv->end;

                    return;
                }
            );
        }
    }

    $cv->end;

    return;
}

sub on_connect ( $self, $ws ) {
    return;
}

sub on_subscribe_event ( $self, $h, $event ) {
    return;
}

sub on_event ( $self, $h, $ev ) {
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
