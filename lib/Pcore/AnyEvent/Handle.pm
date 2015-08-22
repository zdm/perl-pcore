package Pcore::AnyEvent::Handle;

use Pcore;
use parent qw[AnyEvent::Handle];
use AnyEvent::Socket qw[];
use HTTP::Parser::XS qw[HEADERS_NONE];
use Pcore::Proxy;

no Pcore;

our $CACHE = {};

# dafault cache timeout
our $CACHE_TIMEOUT = 4;

sub new ( $self, %args ) {
    if ( $args{connect_timeout} ) {
        my $on_prepare = $args{on_prepare};

        $args{on_prepare} = sub ($h) {
            $on_prepare->($h) if $on_prepare;

            return $args{connect_timeout};
        };
    }

    if ( !$args{proxy} || $args{fh} ) {
        return $self->SUPER::new(%args);
    }
    else {
        my $proxy_type = $args{proxy}->[0];

        my $proxy = ref $args{proxy}->[1] eq 'Pcore::Proxy' ? $args{proxy}->[1] : Pcore::Proxy->new( { uri => $args{proxy}->[1] } );

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
            elsif ( $args{on_error} ) {
                $args{on_error}->( $h, 1, $message );
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

            if ( $proxy_type eq 'http' ) {
                if ( $proxy->is_http ) {
                    $on_connect->();
                }
                else {
                    $h->{on_connect_error}->( $h, 'Proxy is not HTTP proxy', 1 );
                }
            }
            elsif ( $proxy_type eq 'https' ) {
                if ( $args_orig{connect}->[1] == 443 ) {
                    if ( $proxy->is_https ) {
                        _connect_https_proxy( $h, $proxy, $args_orig{connect}, $on_connect );
                    }
                    else {
                        $h->{on_connect_error}->( $h, 'Proxy is not HTTPS proxy', 1 );
                    }
                }
                else {
                    $h->{on_connect_error}->( $h, 'HTTPS proxy can connect only to port 443', 1 );
                }
            }
            elsif ( $proxy_type eq 'connect' ) {
                if ( $proxy->is_connect ) {
                    _connect_https_proxy( $h, $proxy, $args_orig{connect}, $on_connect );
                }
                else {
                    $h->{on_connect_error}->( $h, 'Proxy is not CONNECT proxy', 1 );
                }
            }
            elsif ( index( $proxy_type, 'socks' ) == 0 ) {

                # autimatically define socks proxy type
                if ( $proxy_type eq 'socks' ) {
                    if ( $proxy->is_socks5 ) {
                        _connect_socks5_proxy( $h, $proxy, $args_orig{connect}, $on_connect );
                    }
                    elsif ( $proxy->is_socks4 ) {
                        _connect_socks4_proxy( $h, $proxy, $args_orig{connect}, $on_connect );
                    }
                    elsif ( $proxy->is_socks4a ) {
                        _connect_socks4a_proxy( $h, $proxy, $args_orig{connect}, $on_connect );
                    }
                    else {
                        $h->{on_connect_error}->( $h, 'Proxy is not SOCKS proxy', 1 );
                    }
                }
                elsif ( $proxy_type eq 'socks5' ) {
                    if ( $proxy->is_socks5 ) {
                        _connect_socks5_proxy( $h, $proxy, $args_orig{connect}, $on_connect );
                    }
                    else {
                        $h->{on_connect_error}->( $h, 'Proxy is not SOCKS5 proxy', 1 );
                    }
                }
                elsif ( $proxy_type eq 'socks4' ) {
                    if ( $proxy->is_socks4 ) {
                        $h->{on_connect_error}->( $h, 'Proxy type SOCKS4 is not supported', 1 );

                        # _connect_socks4_proxy( $h, $proxy, $args_orig{connect}, $on_connect );
                    }
                    else {
                        $h->{on_connect_error}->( $h, 'Proxy is not SOCKS4 proxy', 1 );
                    }
                }
                elsif ( $proxy_type eq 'socks4a' ) {
                    if ( $proxy->is_socks4a ) {
                        $h->{on_connect_error}->( $h, 'Proxy type SOCKS4a is not supported', 1 );

                        # _connect_socks4a_proxy( $h, $proxy, $args_orig{connect}, $on_connect );
                    }
                    else {
                        $h->{on_connect_error}->( $h, 'Proxy is not SOCKS4a proxy', 1 );
                    }
                }
                else {
                    $h->{on_connect_error}->( $h, 'Unknown socks proxy type', 1 );
                }
            }
            else {
                $h->{on_connect_error}->( $h, 'Unknown proxy type', 1 );
            }

            return;
        };

        return $self->SUPER::new(%args);
    }
}

sub store ( $self, $id, $timeout = undef ) {

    # do not cache destroyed handles
    return if $self->destroyed;

    my $cache = $CACHE->{$id} ||= [];

    # check, if handle is already cached
    for ( $cache->@* ) {
        return if $_ == $self;
    }

    my $destroy = sub ( $h, @ ) {
        say 'DESTROYED';

        # remove handle from cache
        for ( my $i = 0; $i <= $cache->$#*; $i++ ) {
            if ( $cache->[$i] == $h ) {
                splice $cache->@*, $i, 1;

                last;
            }
        }

        # remove cache id if no more cached handles for this id
        delete $CACHE->{$id} unless $CACHE->{$id}->@*;

        # destroy handle
        $h->destroy;

        return;
    };

    # on error etc., destroy
    $self->on_error($destroy);

    $self->on_eof($destroy);

    $self->on_read($destroy);

    $self->timeout( $timeout || $CACHE_TIMEOUT );

    # store handle
    push $cache->@*, $self;

    return;
}

sub fetch ( $self, $id ) {

    # currently we reuse the MOST RECENTLY USED connection
    my $h = pop $CACHE->{$id}->@*;

    delete $CACHE->{$id} unless $CACHE->{$id}->@*;

    if ($h) {
        $h->on_error(undef);

        $h->on_eof(undef);

        $h->on_read(undef);

        $h->timeout_reset;

        $h->timeout(undef);
    }

    return $h;
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

    $h->push_write( q[CONNECT ] . $connect->[0] . q[:] . $connect->[1] . q[ HTTP/1.1] . $CRLF . ( $proxy->userinfo ? q[Proxy-Authorization: Basic ] . $proxy->userinfo_b64 . $CRLF : $CRLF ) . $CRLF );

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
    if ( $proxy->userinfo ) {
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

sub _connect_socks4_proxy ( $h, $proxy, $connect, $on_connect ) {
    $h->on_timeout(
        sub($h) {
            $h->{on_connect_error}->( $h, q[Connection timed out], 0 );

            return;
        }
    );

    # start handshake
    my $ipn4 = AnyEvent::Socket::parse_ipv4( $connect->[0] );

    my $ident = q[];

    $h->push_write( qq[\x04\x01] . pack( 'n', $connect->[1] ) . $ipn4 . $ident . q[\x00] );

    $h->push_read(
        chunk => 8,
        sub ( $h, $chunk ) {
            my ( $vn, $cd ) = unpack 'CC', $chunk;

            if ( $cd == 90 ) {
                $on_connect->();
            }
            if ( $cd == 91 ) {
                $h->{on_connect_error}->( $h, 'Request rejected or failed', 0 );
            }
            elsif ( $cd == 92 ) {
                $h->{on_connect_error}->( $h, 'Request rejected because SOCKS server cannot connect to identd on the client', 1 );
            }
            elsif ( $cd == 93 ) {
                $h->{on_connect_error}->( $h, 'Request rejected because the client program and identd report different user-ids', 1 );
            }
            else {
                $h->{on_connect_error}->( $h, 'Request rejected', 1 );
            }

            return;
        }
    );

    return;
}

sub _connect_socks4a_proxy ( $h, $proxy, $connect, $on_connect ) {
    $h->{on_connect_error}->( $h, 'Proxy type is not supported', 1 );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 16                   │ Subroutines::ProhibitExcessComplexity - Subroutine "new" with high complexity score (42)                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 182                  │ ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 290, 293, 320, 323,  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## │      │ 326, 414             │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 320, 323, 326, 340   │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 414                  │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AnyEvent::Handle - AnyEvent::Handle with proxy support

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
