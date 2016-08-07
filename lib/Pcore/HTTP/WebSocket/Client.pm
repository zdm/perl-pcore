package Pcore::HTTP::WebSocket::Client;

use Pcore -role;
use Pcore::AE::Handle;

# TODO implement TLS
# TODO implement reconnect / autoreconnect
# websocket_is_connected

sub websocket_connect ( $self, $url, @args ) {
    $url = P->uri($url) if !ref $url;

    my %args = (
        handle_params => {},
        timeout       => undef,
        tls_ctx       => undef,
        bind_ip       => undef,
        proxy         => undef,
        splice @_, 2,
    );

    Pcore::AE::Handle->new(
        $args{handle_params}->%*,
        connect                => $url,
        connect_timeout        => $args{timeout},
        persistent             => 0,
        tls_ctx                => $args{tls_ctx},
        bind_ip                => $args{bind_ip},
        proxy                  => $args{proxy},
        on_proxy_connect_error => sub ( $h, $message, $proxy_error ) {
            return;
        },
        on_connect_error => sub ( $h, $message ) {
            say $message;

            return;
        },
        on_error => sub ( $h, $fatal, $message ) {
            say $message;

            $args{on_error}->($self);

            return;
        },
        on_connect => sub ( $h, $host, $port, $retry ) {

            # start TLS, only if TLS is required and TLS is not established yet
            $h->starttls('connect') if $url->is_secure && !exists $h->{tls};

            # generate websocket key
            my $key = int rand 100_000;

            my $request_path = $url->path->to_uri . ( $url->query ? q[?] . $url->query : q[] );

            my @headers = (    #
                "GET $request_path HTTP/1.1",
                'Host:' . $url->host,
                'Upgrade:websocket',
                'Connection:upgrade',
                'Origin:' . $url,
                'Sec-WebSocket-Version:' . $Pcore::HTTP::WebSocket::Protocol::WEBSOCKET_VERSION,
                'Sec-WebSocket-Key:' . $key,
                ( $self->websocket_protocol           ? 'Sec-WebSocket-Protocol:' . $self->websocket_protocol : () ),
                ( $self->websocket_permessage_deflate ? 'Sec-WebSocket-Extensions:permessage-deflate'         : () ),
            );

            $h->push_write( join( $CRLF, @headers ) . $CRLF . $CRLF );

            $h->read_http_res_headers(
                headers => 1,
                sub ( $h1, $res, $error ) {
                    $self->{_websocket_h} = $h;

                    $self->websocket_listen;

                    $args{on_connect}->($self);

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
## |    3 | 23                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
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
