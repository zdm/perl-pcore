package Pcore::HTTP::WebSocket::Client;

use Pcore;
use Pcore::HTTP::WebSocket::Connection;
use Pcore::Util::Data qw[to_b64];
use Pcore::Util::List qw[pairs];
use Pcore::AE::Handle;

sub connect ( $self, $uri, @ ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    $uri = Pcore->uri($uri) if !ref $uri;

    my %args = (

        # websocket args
        ws_protocol           => undef,
        ws_max_message_size   => 1024 * 1024 * 100,    # 100 Mb
        ws_permessage_deflate => 0,

        # websocket callbacks
        ws_on_disconnect => undef,
        ws_on_text       => undef,
        ws_on_binary     => undef,
        ws_on_pong       => undef,

        # HTTP args
        useragent => "Pcore-HTTP/$Pcore::VERSION",
        headers   => undef,                            # ArrayRef

        # create handle args
        handle_params          => {},
        connect_timeout        => undef,
        tls_ctx                => undef,
        bind_ip                => undef,
        proxy                  => undef,
        on_proxy_connect_error => undef,
        on_connect_error       => undef,
        on_connect             => undef,
        splice @_, 2,
    );

    Pcore::AE::Handle->new(
        persistent => 0,
        $args{handle_params}->%*,
        connect         => $uri,
        connect_timeout => $args{connect_timeout},
        tls_ctx         => $args{tls_ctx},
        bind_ip         => $args{bind_ip},
        proxy           => $args{proxy},
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
                'Upgrade:websocket',
                'Connection:upgrade',
                "Sec-WebSocket-Version:$Pcore::HTTP::WebSocket::Connection::WEBSOCKET_VERSION",
                "Sec-WebSocket-Key:$sec_websocket_key",
                ( $args{ws_protocol}           ? "Sec-WebSocket-Protocol:$args{ws_protocol}"   : () ),
                ( $args{ws_permessage_deflate} ? 'Sec-WebSocket-Extensions:permessage-deflate' : () ),
                ( $args{useragent}             ? "User-Agent:$args{useragent}"                 : () ),
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
                        elsif ( !$res_headers->{SEC_WEBSOCKET_ACCEPT} || $res_headers->{SEC_WEBSOCKET_ACCEPT} ne Pcore::HTTP::WebSocket::Connection->challenge($sec_websocket_key) ) {
                            $error_status = 596;
                            $error_reason = q[Invalid WebSocket SEC_WEBSOCKET_ACCEPT];
                        }

                        # check protocol
                        else {
                            if ( $res_headers->{SEC_WEBSOCKET_PROTOCOL} ) {
                                if ( !$args{ws_protocol} || $res_headers->{SEC_WEBSOCKET_PROTOCOL} !~ /\b$args{ws_protocol}\b/smi ) {
                                    $error_status = 596;
                                    $error_reason = qq[WebSocket server returned unsupported protocol "$res_headers->{SEC_WEBSOCKET_PROTOCOL}"];
                                }
                            }
                            elsif ( $args{ws_protocol} ) {
                                $error_status = 596;
                                $error_reason = q[WebSocket server returned no protocol];
                            }
                        }
                    }

                    if ($error_status) {
                        if ( $args{on_connect_error} ) {
                            $args{on_connect_error}->( $error_status, $error_reason );
                        }
                        else {
                            die qq[WebSocket connect error: $error_status, $error_reason];
                        }
                    }
                    else {
                        my $permessage_deflate = 0;

                        # check and set extensions
                        if ( $res_headers->{SEC_WEBSOCKET_EXTENSIONS} ) {
                            $permessage_deflate = 1 if $args{ws_permessage_deflate} && $res_headers->{SEC_WEBSOCKET_EXTENSIONS} =~ /\bpermessage-deflate\b/smi;
                        }

                        my $ws = bless {
                            h                  => $h,
                            max_message_size   => $args{ws_max_message_size},
                            permessage_deflate => $permessage_deflate,
                            _send_masked       => 1,                            # client always send masked frames
                            on_disconnect      => $args{ws_on_disconnect},
                            on_text            => $args{ws_on_text},
                            on_binary          => $args{ws_on_binary},
                            on_pong            => $args{ws_on_pong},
                          },
                          'Pcore::HTTP::WebSocket::Connection';

                        $ws->start_listen;

                        $args{on_connect}->( $ws, $res_headers ) if $args{on_connect};
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
## |    3 | 9                    | Subroutines::ProhibitExcessComplexity - Subroutine "connect" with high complexity score (38)                   |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::WebSocket::Client

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
