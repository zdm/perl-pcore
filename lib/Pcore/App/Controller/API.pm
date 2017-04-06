package Pcore::App::Controller::API;

use Pcore -role, -result;
use Pcore::Util::Data qw[from_json to_json from_uri_query];
use Pcore::WebSocket;

with qw[Pcore::App::Controller];

sub run ( $self, $req ) {

    # WebSocket connect handler
    if ( $req->is_websocket_connect_request ) {
        Pcore::WebSocket->accept_ws(
            'pcore', $req,
            sub ( $ws, $req, $accept, $reject ) {

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
                            $accept->(
                                {   max_message_size   => 1_024 * 1_024 * 100,    # 100 Mb
                                    pong_timeout       => 50,
                                    permessage_deflate => 0,
                                    on_connect         => sub ($ws) {
                                        return;
                                    },
                                    on_disconnect => sub ( $ws, $status ) {
                                        return;
                                    },
                                    on_rpc_call => sub ( $ws, $req, $method, $args = undef ) {
                                        $ws->{auth}->api_call_arrayref( $method, $args, $req );

                                        return;
                                    }
                                }
                            );
                        }

                        return;
                    }
                );

                return;
            },
        );

        return;
    }

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

    my $msg;

    # decode API request
    if ( !$env->{CONTENT_TYPE} || $env->{CONTENT_TYPE} =~ m[\bapplication/json\b]smi ) {
        $msq = eval { from_json $req->body };

        # content decode error
        if ($@) {
            $req->( [ 400, q[Error decoding JSON request body] ] )->finish;

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
                $msg = [$msg] if ref $msg ne 'ARRAY';

                my ( $response, @headers );

                my $cv = AE::cv sub {

                    # add Content-Type header
                    push @headers, ( 'Content-Type' => 'application/json' );

                    # write HTTP response
                    $req->( 200, \@headers, to_json $response)->finish;

                    # free HTTP request object
                    undef $req;

                    return;
                };

                $cv->begin;

                for my $tx ( $msg->@* ) {

                    # check message type
                    if ( !$tx->{type} || $tx->{type} ne 'rpc' ) {
                        push $response->@*,
                          { tid     => $tx->{tid},
                            type    => 'exception',
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
                            type    => 'exception',
                            message => {
                                status => 400,
                                reason => 'Method is required',
                            },
                          };

                        next;
                    }

                    $cv->begin;

                    # combine method with action
                    my $method_id = $tx->{action} ? q[/] . ( $tx->{action} =~ s[[.]][/]smgr ) . "/$tx->{method}" : $tx->{method};

                    $auth->api_call_arrayref(
                        $method_id,
                        $tx->{data},
                        sub ($res) {
                            push @headers, $res->{headers}->@* if $res->{headers};

                            if ( $res->is_success ) {
                                push $response->@*,
                                  { tid    => $tx->{tid},
                                    type   => 'rpc',
                                    result => $res,
                                  };
                            }
                            else {
                                push $response->@*,
                                  { tid     => $tx->{tid},
                                    type    => 'exception',
                                    message => $res,
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 9                    | Subroutines::ProhibitExcessComplexity - Subroutine "run" with high complexity score (22)                       |
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
