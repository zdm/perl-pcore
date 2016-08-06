package Pcore::HTTP::WebSocket::Client;

use Pcore -role;
use Pcore::AE::Handle;

# TODO implement TLS

sub websocket_connect ( $self, $url, @ ) {
    my %args = (
        on_error        => undef,
        on_connect      => undef,
        connect_timeout => 30,
        splice @_, 2
    );

    Pcore::AE::Handle->new(
        $args->{handle_params}->%*,
        connect                => $args->{url},
        connect_timeout        => $args->{timeout},
        timeout                => $args->{timeout},
        persistent             => $args->{persistent},
        session                => $args->{session},
        tls_ctx                => $args->{tls_ctx},
        bind_ip                => $args->{bind_ip},
        proxy                  => $args->{proxy},
        on_proxy_connect_error => sub ( $h, $message, $proxy_error ) {
            $runtime->{finish}->( 594, $message );

            return;
        },
        on_connect_error => sub ( $h, $message ) {
            $runtime->{finish}->( $runtime->{on_error_status}, $message );

            return;
        },
        on_error => sub ( $h, $fatal, $message ) {
            $runtime->{finish}->( $runtime->{on_error_status}, $message );

            return;
        },
        on_connect => sub ( $h, $host, $port, $retry ) {
            if ( $h->{proxy} && $h->{proxy_type} && $h->{proxy_type} == $PROXY_TYPE_HTTP && $h->{proxy}->userinfo ) {
                $args->{headers}->{PROXY_AUTHORIZATION} = 'Basic ' . $h->{proxy}->userinfo_b64;
            }
            else {
                delete $args->{headers}->{PROXY_AUTHORIZATION};
            }

            $cb->($h);

            return;
        },
    );

    Pcore::AE::Handle->new(
        %args,
        connect  => $url,
        on_error => sub ( $h, @ ) {
            say 'ERRRO';

            return;
        },
        on_connect => sub ( $h, @ ) {

            # start TLS, only if TLS is required and TLS is not established yet
            $h->starttls('connect') if $url->is_secure && !exists $h->{tls};

            my $key = int rand 100_000;

            $request_path = $args->{url}->path->to_uri . ( $args->{url}->query ? q[?] . $args->{url}->query : q[] );

            my @headers = (    #
                "GET $request_path HTTP/1.1",
                'Host:' . $url->host,
                'Upgrade:websocket',
                'Connection:upgrade',
                'Origin:' . $url,
                'Sec-WebSocket-Version:' . $Pcore::HTTP::WebSocket::SubProtocol::WS_VERSION,
                'Sec-WebSocket-Key:' . $key,
                ( $self->websocket_subprotocol  ? 'Sec-WebSocket-Protocol:' . $self->websocket_subprotocol : () ),
                ( $self->ext_permessage_deflate ? 'Sec-WebSocket-Extensions:permessage-deflate'            : () ),
            );

            $h->push_write( join( $CRLF, @headers ) . $CRLF . $CRLF );

            $h->read_http_res_headers(
                headers => 1,
                sub ( $h1, $res, $error ) {
                    $self->{h} = $h;

                    $self->listen;

                    $args{on_connect}->($self);

                    return;
                }
            );

            return;
        }
    );

    return $self;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 17                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 9                    | CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    |
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
