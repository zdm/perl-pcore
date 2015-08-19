package Pcore::AnyEvent::Handle;

use Pcore;
use parent qw[AnyEvent::Handle];
use AnyEvent::Socket qw[];
use HTTP::Parser::XS qw[HEADERS_NONE];

no Pcore;

sub new ( $self, %args ) {
    if ( !$args{proxy} || $args{fh} ) {
        return $self->SUPER::new(%args);
    }
    else {
        my $proxy_type = $args{proxy}->[0];

        my $proxy = $args{proxy}->[1];

        my %args_orig = (
            connect          => $args{connect},
            on_connect_error => $args{on_connect_error},
            on_connect       => $args{on_connect},
        );

        # redefine "connect"
        $args{connect} = [ $proxy->host, $proxy->port ];

        # redefine "on_connect_error"
        $args{on_connect_error} = sub ( $h, $message, $proxy = 1 ) {
            $h->destroy;

            if ( $proxy && $args{on_proxy_connect_error} ) {
                $args{on_proxy_connect_error}->( $h, $message );
            }
            elsif ( $args_orig{on_connect_error} ) {
                $args_orig{on_connect_error}->( $h, $message );
            }
            elsif ( $args_orig{on_error} ) {
                $args_orig{on_error}->( $h, 1, $message );
            }
            else {
                die $message;
            }

            return;
        };

        # redefine "on_connect"
        $args{on_connect} = sub ( $h, $host, $port, $retry ) {
            my $on_connect = sub {

                # restore orig callbacks
                $h->on_timeout( $args_orig{on_timeout} ) if $args_orig{on_timeout};

                # call orig "on_connect" cb
                $args_orig{on_connect}->( $h, $host, $port, $retry ) if $args_orig{on_connect};

                return;
            };

            if ( $proxy_type eq 'socks' ) {
                if ( $proxy->is_socks5 ) {
                    _connect_socks5_proxy( $h, $proxy, $args_orig{connect}, $on_connect );
                }
                else {
                    $h->{on_connect_error}->( $h, 'Proxy type is not supported', 1 );
                }
            }
            elsif ( $proxy_type eq 'https' ) {
                _connect_https_proxy( $h, $proxy, $args_orig{connect}, $on_connect );
            }
            elsif ( $proxy_type eq 'http' ) {
                $on_connect->();
            }
            else {
                $h->{on_connect_error}->( $h, 'Unknown proxy type', 1 );
            }

            return;
        };

        return $self->SUPER::new(%args);
    }
}

sub _connect_https_proxy ( $h, $proxy, $connect, $on_connect ) {
    state $qr_nlnl = qr/(?<![^\n])\r?\n/sm;

    # TODO how to clarify, what this timeout means, proxy not respond or tunnel creation timeout (target server not respond)?
    # currently we assume, that this is tunnel creation error
    $h->on_timeout(
        sub($h) {
            $h->{on_connect_error}->( $h, q[Connection timed out], 0 );

            return;
        }
    );

    $h->push_write( q[CONNECT ] . $connect->[0] . q[:] . $connect->[1] . q[ HTTP/1.0] . $CRLF . ( $proxy->auth ? q[Proxy-Authorization: Basic ] . $proxy->auth_b64 . $CRLF : $CRLF ) . $CRLF );

    $h->push_read(
        line => $qr_nlnl,
        sub {
            # parse HTTP response headers
            my ( $len, $minor_version, $status, $message ) = HTTP::Parser::XS::parse_http_response( $_[1] . $CRLF, HEADERS_NONE );

            if ( $len < 0 ) {    # $len = -1 - incomplete headers, -2 - errors, >= 0 - headers length
                $h->{on_connect_error}->( $h, q[Invalid proxy connect response], 1 );
            }
            else {
                if ( $status == 200 ) {
                    $on_connect->();
                }
                elsif ( $status == 503 ) {    # error creating tunnel
                    $h->{on_connect_error}->( $h, $message, 0 );
                }
                else {
                    $h->{on_connect_error}->( $h, $message, 1 );
                }
            }

            return;
        }
    );

    return;
}

sub _connect_socks5_proxy ( $h, $proxy, $connect, $on_connect ) {
    $h->on_timeout(
        sub($h) {
            $h->{on_connect_error}->( $h, q[Connection timed out], 1 );

            return;
        }
    );

    # start handshake
    if ( $proxy->auth ) {
        $h->push_write(qq[\x05\x02\x00\x02]);
    }
    else {
        $h->push_write(qq[\x05\x01\x00]);
    }

    $h->push_read(
        chunk => 2,
        sub ( $h, $chunk ) {
            my ( $ver, $method ) = unpack 'C*', $chunk;

            if ( $method == 255 ) {    # no valid auth method was proposed
                $h->{on_connect_error}->( $h, 'No authorization method was found', 1 );
            }
            elsif ( $method == 2 ) {    # start username / password authorization
                $h->{on_connect_error}->( $h, 'Authorization method not supported', 1 );
            }
            elsif ( $method == 0 ) {    # no authorization needed

                # timeout - tunnel creation timeout error
                $h->on_timeout(
                    sub($h) {
                        $h->{on_connect_error}->( $h, q[Connection timed out], 0 );

                        return;
                    }
                );

                # detect destination addr type
                if ( my $ipn4 = AnyEvent::Socket::parse_ipv4( $connect->[0] ) ) {    # IPv4 addr
                    $h->push_write( qq[\x05\x01\x00\x01] . $ipn4 . pack( 'n', $connect->[1] ) );
                }
                elsif ( my $ipn6 = AnyEvent::Socket::parse_ipv6( $connect->[0] ) ) {    # IPv6 addr
                    $h->push_write( qq[\x05\x01\x00\x04] . $ipn6 . pack( 'n', $connect->[1] ) );
                }
                else {                                                                  # domain name
                    $h->push_write( qq[\x05\x01\x00\x03] . pack( 'C', length $connect->[0] ) . $connect->[0] . pack( 'n', $connect->[1] ) );
                }

                $h->push_read(
                    chunk => 4,
                    sub ( $h, $chunk ) {
                        $h->on_timeout(
                            sub($h) {
                                $h->{on_connect_error}->( $h, q[Connection timed out], 1 );

                                return;
                            }
                        );

                        my ( $ver, $rep, $rsv, $atyp ) = unpack( 'C*', $chunk );    ## no critic qw[Variables::ProhibitReusedNames]

                        if ( $rep == 0 ) {
                            if ( $atyp == 1 ) {                                     # IPv4 addr, 4 bytes
                                $h->push_read(                                      # read IPv4 addr (4 bytes) + port (2 bytes)
                                    chunk => 6,
                                    sub ( $h, $chunk ) {
                                        $on_connect->();

                                        return;
                                    }
                                );
                            }
                            elsif ( $atyp == 3 ) {                                  # domain name
                                $h->push_read(                                      # read domain name length
                                    chunk => 1,
                                    sub ( $h, $chunk ) {
                                        $h->push_read(                              # read domain name + port (2 bytes)
                                            chunk => unpack( 'C', $chunk ) + 2,
                                            sub ( $h, $chunk ) {
                                                $on_connect->();

                                                return;
                                            }
                                        );

                                        return;
                                    }
                                );
                            }
                            if ( $atyp == 4 ) {    # IPv6 addr, 16 bytes
                                $h->push_read(     # read IPv6 addr (16 bytes) + port (2 bytes)
                                    chunk => 18,
                                    sub ( $h, $chunk ) {
                                        $on_connect->();

                                        return;
                                    }
                                );
                            }
                        }
                        else {
                            $h->{on_connect_error}->( $h, q[Tunnel creation error], 0 );
                        }

                        return;
                    }
                );

                return;
            }
            else {
                $h->{on_connect_error}->( $h, 'Authorization method not supported', 1 );
            }
        }
    );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 140, 143, 170, 173,  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## │      │ 176                  │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 170, 173, 176, 190   │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AnyEvent::Handle

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
