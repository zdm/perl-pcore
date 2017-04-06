package Pcore::WebSocket;

use Pcore;
use Pcore::Util::Scalar qw[refaddr];
use Pcore::Util::Data qw[to_b64];
use Pcore::Util::List qw[pairs];
use Pcore::WebSocket::Handle;
use Pcore::AE::Handle;

our $HANDLE = {};

sub accept ( $self, $protocol, $req, $on_accept ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]

    # this is websocket connect request
    if ( $req->is_websocket_connect_request ) {
        my $env = $req->{env};

        # websocket version is not specified or not supported
        return $req->return_xxx( [ 400, q[Unsupported WebSocket version] ] ) if !$env->{HTTP_SEC_WEBSOCKET_VERSION} || $env->{HTTP_SEC_WEBSOCKET_VERSION} ne $Pcore::WebSocket::Handle::WEBSOCKET_VERSION;

        # websocket key is not specified
        return $req->return_xxx( [ 400, q[WebSocket SEC_WEBSOCKET_KEY header is required] ] ) if !$env->{HTTP_SEC_WEBSOCKET_KEY};

        # check websocket protocol
        if ($protocol) {
            if ( !$env->{HTTP_SEC_WEBSOCKET_PROTOCOL} || $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} !~ /\b$protocol\b/smi ) {
                return $req->return_xxx( [ 400, q[Unsupported WebSocket protocol] ] );
            }
        }
        elsif ( $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} ) {
            return $req->return_xxx( [ 400, q[Unsupported WebSocket protocol] ] );
        }

        # load wesocket protocol class
        my $implementation = $protocol || 'raw';

        eval { require "Pcore/Websocket/Protocol/$implementation.pm" };    ## no critic qw[Modules::RequireBarewordIncludes]

        if ($@) {
            return $req->return_xxx( [ 400, q[Unsupported WebSocket protocol] ] );
        }

        # create empty websocket object
        my $ws = bless {}, "Pcore::WebSocket::Protocol::$implementation";

        my $accept = sub ( $ws_cfg = undef, $headers = undef ) {
            $ws->@{ keys $ws_cfg->%* } = values $ws_cfg->%* if $ws_cfg;

            my $permessage_deflate = 0;

            # check and set extensions
            if ( $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} ) {

                # set ext_permessage_deflate, only if enabled locally
                $permessage_deflate = 1 if $ws->permessage_deflate && $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} =~ /\bpermessage-deflate\b/smi;
            }

            # create response headers
            my @headers = (    #
                'Sec-WebSocket-Accept' => $ws->get_challenge( $env->{HTTP_SEC_WEBSOCKET_KEY} ),
                ( $protocol           ? ( 'Sec-WebSocket-Protocol'   => $protocol )            : () ),
                ( $permessage_deflate ? ( 'Sec-WebSocket-Extensions' => 'permessage-deflate' ) : () ),
            );

            # add custom headers
            push @headers, $headers->@* if $headers;

            # accept websocket connection
            $ws->{h} = $req->accept_websocket( \@headers );

            # store ws handle
            $HANDLE->{ refaddr $ws} = $ws;

            # connected
            $ws->on_connect;

            return;
        };

        my $decline = sub ( $status = 400, $headers = undef ) {
            $req->( $status, $headers )->finish;

            return;
        };

        $on_accept->( $ws, $req, $accept, $decline );

        return;
    }

    # this is NOT websocket connect request
    else {
        $req->return_xxx( [ 400, q[Not a WebSocket connect request] ] );
    }

    return;
}

sub connect ( $self, $protocol, $uri, @ ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]

    # permessage_deflate
    my %args = splice @_, 3;

    my $class = eval { P->class->load( $protocol || 'raw', ns => 'Pcore::WebSocket::Protocol' ) };

    my $on_error = sub ( $status, $reason ) {
        if ( $args{on_connect_error} ) {
            $args{on_connect_error}->( $status, $reason );
        }
        elsif ( $args{on_error} ) {
            $args{on_error}->( $status, $reason );
        }
        else {
            die qq[WebSocket connect error: $status, $reason];
        }

        return;
    };

    if ($@) {
        $on_error->( 400, 'WebSocket protocol is not supported' );

        return;
    }

    $uri = Pcore->uri($uri) if !ref $uri;

    Pcore::AE::Handle->new(
        $args{handle_params}->%*,
        persistent             => 0,
        connect                => $uri,
        connect_timeout        => $args{connect_timeout},
        tls_ctx                => $args{tls_ctx},
        bind_ip                => $args{bind_ip},
        proxy                  => $args{proxy},
        on_proxy_connect_error => sub ( $h, $reason, $proxy_error ) {
            if ( $args{on_proxy_connect_error} ) {
                $args{on_proxy_connect_error}->( 594, $reason, $proxy_error );
            }
            elsif ( $args{on_connect_error} ) {
                $args{on_proxy_connect_error}->( 594, $reason );
            }
            else {
                die qq[WebSocket proxy connect error: 594, $reason, $proxy_error];
            }

            return;
        },
        on_connect_error => sub ( $h, $reason ) {
            if ( $args{on_connect_error} ) {
                $args{on_connect_error}->( 595, $reason );
            }
            else {
                die qq[WebSocket connect error: 595, $reason];
            }

            return;
        },
        on_error => sub ( $h, $fatal, $reason ) {
            if ( $args{on_connect_error} ) {
                $args{on_connect_error}->( 596, $reason );
            }
            else {
                die qq[WebSocket connect error: 596, $reason];
            }

            return;
        },
        on_connect => sub ( $h, $host, $port, $retry ) {

            # start TLS, only if TLS is required and TLS is not established yet
            $h->starttls('connect') if $uri->is_secure && !exists $h->{tls};

            # generate websocket key
            my $sec_websocket_key = to_b64 rand 100_000, q[];

            my $request_path = $uri->path->to_uri . ( $uri->query ? q[?] . $uri->query : q[] );

            my @headers = (    #
                "GET $request_path HTTP/1.1",
                'Host:' . $uri->host,
                "User-Agent:Pcore-HTTP/$Pcore::VERSION",
                'Upgrade:websocket',
                'Connection:upgrade',
                "Sec-WebSocket-Version:$Pcore::WebSocket::Handle::WEBSOCKET_VERSION",
                "Sec-WebSocket-Key:$sec_websocket_key",
                ( $protocol                 ? "Sec-WebSocket-Protocol:$protocol"            : () ),
                ( $args{permessage_deflate} ? 'Sec-WebSocket-Extensions:permessage-deflate' : () ),
            );

            push @headers, map {"$_->[0]:$_->[1]"} pairs $args{headers}->@* if $args{headers};

            $h->push_write( join( $CRLF, @headers ) . $CRLF . $CRLF );

            $h->read_http_res_headers(
                headers => 1,
                sub ( $h1, $headers, $error_reason ) {
                    my $error_status;

                    my $res_headers;

                    if ($error_reason) {

                        # headers parsing error
                        $error_status = 596;
                    }
                    else {
                        $res_headers = $headers->{headers};

                        # check response status
                        if ( $headers->{status} != 101 ) {
                            $error_status = $headers->{status};
                            $error_reason = $headers->{reason};
                        }

                        # check response connection headers
                        elsif ( !$res_headers->{CONNECTION} || !$res_headers->{UPGRADE} || $res_headers->{CONNECTION} !~ /\bupgrade\b/smi || $res_headers->{UPGRADE} !~ /\bwebsocket\b/smi ) {
                            $error_status = 596;
                            $error_reason = q[WebSocket handshake error];
                        }

                        # check SEC_WEBSOCKET_ACCEPT
                        elsif ( !$res_headers->{SEC_WEBSOCKET_ACCEPT} || $res_headers->{SEC_WEBSOCKET_ACCEPT} ne Pcore::WebSocket::Handle->get_challenge($sec_websocket_key) ) {
                            $error_status = 596;
                            $error_reason = q[Invalid WebSocket SEC_WEBSOCKET_ACCEPT];
                        }

                        # check protocol
                        else {
                            if ( $res_headers->{SEC_WEBSOCKET_PROTOCOL} ) {
                                if ( !$protocol || $res_headers->{SEC_WEBSOCKET_PROTOCOL} !~ /\b$protocol\b/smi ) {
                                    $error_status = 596;
                                    $error_reason = qq[WebSocket server returned unsupported protocol "$res_headers->{SEC_WEBSOCKET_PROTOCOL}"];
                                }
                            }
                            elsif ($protocol) {
                                $error_status = 596;
                                $error_reason = q[WebSocket server returned no protocol];
                            }
                        }
                    }

                    if ($error_status) {
                        $on_error->( $error_status, $error_reason );
                    }
                    else {
                        my $permessage_deflate = 0;

                        # check and set extensions
                        if ( $res_headers->{SEC_WEBSOCKET_EXTENSIONS} ) {
                            $permessage_deflate = 1 if $args{permessage_deflate} && $res_headers->{SEC_WEBSOCKET_EXTENSIONS} =~ /\bpermessage-deflate\b/smi;
                        }

                        my $ws = bless {
                            h                  => $h,
                            max_message_size   => $args{max_message_size},
                            permessage_deflate => $permessage_deflate,
                            _send_masked       => 1,                         # client always send masked frames
                          },
                          $class;

                        $ws->on_connect;

                        $args{on_connect}->( $ws, $res_headers );
                    }

                    return;
                }
            );

            return;
        },
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
## |    3 | 37                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 99                   | Subroutines::ProhibitExcessComplexity - Subroutine "connect" with high complexity score (39)                   |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::WebSocket

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
