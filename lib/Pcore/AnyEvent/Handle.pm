package Pcore::AnyEvent::Handle;

use Pcore;
use parent qw[AnyEvent::Handle];
use AnyEvent::Socket qw[];
use HTTP::Parser::XS qw[HEADERS_NONE];
use Pcore::Proxy;
use Scalar::Util qw[refaddr];    ## no critic qw[Modules::ProhibitEvilModules];
use Const::Fast qw[const];

no Pcore;

const our $PROXY_CONNECT_ERROR   => 1;
const our $PROXY_HANDSHAKE_ERROR => 2;
const our $CONNECT_ERROR         => 3;

const our $PROXY_TYPE_CONNECT => 1;
const our $PROXY_TYPE_HTTPS   => 2;
const our $PROXY_TYPE_SOCKS5  => 3;
const our $PROXY_TYPE_SOCKS4  => 4;
const our $PROXY_TYPE_SOCKS4a => 5;
const our $PROXY_TYPE_HTTP    => 6;

our $CACHE = {};

# default cache timeout
our $CACHE_TIMEOUT = 4;

sub new ( $self, %args ) {
    if ( $args{connect_timeout} ) {
        my $on_prepare = $args{on_prepare};

        my $connect_timeout = $args{connect_timeout};

        $args{on_prepare} = sub ($h) {
            $on_prepare->($h) if $on_prepare;

            return $connect_timeout;
        };
    }

    if ( $args{fh} ) {
        return $self->SUPER::new(%args);
    }
    elsif ( !$args{proxy} ) {
        return $self->SUPER::new(%args);
    }
    else {
        my $proxy = ref $args{proxy} ? $args{proxy} : Pcore::Proxy->new( $args{proxy} );

        # select proxy type
        if ( !$args{proxy_type} ) {

            if ( $args{connect}->[1] == 443 ) {
                $args{proxy_type} = $proxy->is_https || $proxy->is_socks5 || $proxy->is_http;
            }
            else {
                $args{proxy_type} = $proxy->is_connect || $proxy->is_socks5 || $proxy->is_http;
            }
        }

        my %args_orig = (
            connect => $args{connect},    # TODO convert hostname to the punycode, if needed

            # callbacks
            on_connect_error => $args{on_connect_error},
            on_timeout       => $args{on_timeout},
            on_error         => $args{on_error},
            on_connect       => $args{on_connect},
        );

        # redefine "connect"
        $args{connect} = [ $proxy->host->name, $proxy->port ];

        # redefine "on_connect_error"
        $args{on_connect_error} = sub ( $h, $message, $error_type = $PROXY_CONNECT_ERROR ) {
            $h->destroy if $h;

            if ( $args{on_proxy_connect_error} and $error_type != $CONNECT_ERROR ) {
                $args{on_proxy_connect_error}->( $h, $message, $error_type == $PROXY_CONNECT_ERROR ? 1 : 0 );
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

        if ( !$args{proxy_type} ) {
            $args{on_connect_error}->( undef, 'Invalid proxy type', $PROXY_CONNECT_ERROR );

            return;
        }
        elsif ( $args{proxy_type} == $PROXY_TYPE_SOCKS4 or $args{proxy_type} == $PROXY_TYPE_SOCKS4a ) {
            $args{on_connect_error}->( undef, 'Proxy type is not supported', $PROXY_CONNECT_ERROR );

            return;
        }
        elsif ( $args{proxy_type} == $PROXY_TYPE_SOCKS5 or $args{proxy_type} == $PROXY_TYPE_CONNECT or $args{proxy_type} = $PROXY_TYPE_HTTPS ) {
            $args{timeout} = $args{connect_timeout} if $args{connect_timeout};

            # all proxy connection timeouts will be handled by "on_error" callback
            delete $args{on_timeout};

            # redefine "on_error" to handle proxy connection errors
            # by default all errors - are proxy connect errors
            $args{on_error} = sub ( $h, $fatal, $message ) {
                $args{on_connect_error}->( $h, $message, $PROXY_HANDSHAKE_ERROR );

                return;
            };

            # redefine "on_connect"
            $args{on_connect} = sub ( $h, $host, $port, $retry ) {
                my $on_connect = sub {

                    # restore orig. settings
                    $h->timeout( $args{timeout} );

                    # restore orig. callbacks
                    $h->on_timeout( $args_orig{on_timeout} );

                    $h->on_error( $args_orig{on_error} );

                    # call orig "on_connect" cb
                    $args_orig{on_connect}->( $h, $host, $port, $retry ) if $args_orig{on_connect};

                    return;
                };

                if ( $args{proxy_type} == $PROXY_TYPE_SOCKS5 ) {
                    _connect_socks5_proxy( $h, $proxy, $args_orig{connect}, $on_connect, $args{on_connect_error} );
                }
                elsif ( $args{proxy_type} == $PROXY_TYPE_CONNECT or $args{proxy_type} == $PROXY_TYPE_HTTPS ) {
                    _connect_connect_proxy( $h, $proxy, $args_orig{connect}, $on_connect, $args{on_connect_error} );
                }

                return;
            };
        }

        return $self->SUPER::new(%args);
    }
}

sub store ( $self, $id, $timeout = undef ) {

    # do not cache destroyed handles
    return if $self->destroyed;

    my $cache = $CACHE->{$id} ||= {
        h     => [],
        index => {},
    };

    my $refaddr = refaddr($self);

    # check, if handle is already cached
    return if exists $cache->{index}->{$refaddr};

    my $destroy = sub ( $h, @ ) {

        # remove handle from cache
        for ( my $i = 0; $i <= $cache->{h}->$#*; $i++ ) {
            if ( refaddr( $cache->{h}->[$i] ) == $refaddr ) {
                splice $cache->{h}->@*, $i, 1;

                delete $cache->{index}->{$refaddr};

                last;
            }
        }

        # remove cache id if no more cached handles for this id
        delete $CACHE->{$id} unless $CACHE->{$id}->{h}->@*;

        # destroy handle
        $h->destroy;

        return;
    };

    # on error etc., destroy
    $self->on_error($destroy);

    $self->on_eof($destroy);

    $self->on_read($destroy);

    $self->on_timeout(undef);

    $self->timeout_reset;

    $self->timeout( $timeout || $CACHE_TIMEOUT );

    # store handle
    push $cache->{h}->@*, $self;

    $cache->{index}->{$refaddr} = 1;

    return;
}

sub fetch ( $self, $id ) {
    return unless $CACHE->{$id};

    # currently we reuse the MOST RECENTLY USED connection
    my $h = pop $CACHE->{$id}->{h}->@*;

    if ($h) {
        delete $CACHE->{$id}->{index}->{ refaddr($h) };

        if ( $h->destroyed ) {
            undef $h;
        }
        else {
            $h->on_error(undef);

            $h->on_eof(undef);

            $h->on_read(undef);

            $h->timeout_reset;

            $h->timeout(0);
        }
    }

    delete $CACHE->{$id} unless $CACHE->{$id}->{h}->@*;

    return $h;
}

sub _connect_socks5_proxy ( $h, $proxy, $connect, $on_connect, $on_connect_error ) {

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
                $on_connect_error->( $h, 'No authorization method was found', $PROXY_HANDSHAKE_ERROR );
            }
            elsif ( $method == 2 ) {    # start username / password authorization
                $on_connect_error->( $h, 'Authorization method not supported', $PROXY_HANDSHAKE_ERROR );
            }
            elsif ( $method == 0 ) {    # no authorization needed

                # handle tunnel creation error as CONNECT_ERROR
                $h->on_error(
                    sub($h, $fatal, $message) {
                        $on_connect_error->( $h, $message, $CONNECT_ERROR );

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
                        $h->on_error(
                            sub($h, $fatal, $message) {
                                $on_connect_error->( $h, $message, $PROXY_HANDSHAKE_ERROR );

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
                            $on_connect_error->( $h, q[Tunnel creation error], $CONNECT_ERROR );
                        }

                        return;
                    }
                );

                return;
            }
            else {
                $on_connect_error->( $h, 'Authorization method is not supported', $PROXY_HANDSHAKE_ERROR );
            }
        }
    );

    return;
}

sub _connect_connect_proxy ( $h, $proxy, $connect, $on_connect, $on_connect_error ) {
    state $qr_nlnl = qr/(?<![^\n])\r?\n/sm;

    # TODO how to clarify, what this timeout means, proxy not respond or tunnel creation timeout (target server not respond)?
    # currently we assume, that this is NOT THE PROXY CONNECTION ERROR
    $h->on_error(
        sub($h, $fatal, $message) {
            $on_connect_error->( $h, $message, $CONNECT_ERROR );

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
                $on_connect_error->( $h, q[Invalid proxy connect response], $PROXY_HANDSHAKE_ERROR );
            }
            else {
                if ( $status == 200 ) {
                    $on_connect->();
                }
                elsif ( $status == 503 ) {    # error creating tunnel
                    $on_connect_error->( $h, $status . q[ - ] . $message, $CONNECT_ERROR );
                }
                else {
                    $on_connect_error->( $h, $status . q[ - ] . $message, $PROXY_HANDSHAKE_ERROR );
                }
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
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 29                   │ Subroutines::ProhibitExcessComplexity - Subroutine "new" with high complexity score (32)                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 240, 354             │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 170                  │ ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 244, 247, 274, 277,  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## │      │ 280                  │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │                      │ Documentation::RequirePodLinksIncludeText                                                                      │
## │      │ 429                  │ * Link L<AnyEvent::Handle> on line 435 does not specify text                                                   │
## │      │ 429                  │ * Link L<AnyEvent::Handle> on line 443 does not specify text                                                   │
## │      │ 429                  │ * Link L<AnyEvent::Handle> on line 471 does not specify text                                                   │
## │      │ 429                  │ * Link L<AnyEvent::Handle> on line 487 does not specify text                                                   │
## │      │ 429                  │ * Link L<AnyEvent::Socket> on line 487 does not specify text                                                   │
## │      │ 429, 429             │ * Link L<Pcore::Proxy> on line 453 does not specify text                                                       │
## │      │ 429                  │ * Link L<Pcore::Proxy> on line 487 does not specify text                                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 21                   │ NamingConventions::Capitalization - Constant "$PROXY_TYPE_SOCKS4a" is not all upper case                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 274, 277, 280, 294   │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AnyEvent::Handle - L<AnyEvent::Handle> subclass with proxy support

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

Refer to the L<AnyEvent::Handle> for the other base class attributes.

=head2 connect_timeout = <seconds>

Connect timeout in seconds.

=head2 proxy = [ <proxy_type>, <proxy> ]

    proxy => [ 'socks5', 'connect://127.0.0.1:8080?socks5' ],

Proxy to use. First argument - is a preferred proxy type. Second argument - L<Pcore::Proxy> object, or HashRef, that will be passed to the L<Pcore::Proxy> constructor.

=head2 on_proxy_connect_error = sub ( $self, $message )

    on_proxy_connect_error => sub ( $h, $message ) {
        return;
    },

Error callback, called in the case of the proxy connection error.

=head1 CLASS METHODS

=head2 fetch ( $self, $id )

Fetch stored connection from the cache. Return C<undef> if no cached connections for current id was found.

=head1 METHODS

Refer to the L<AnyEvent::Handle> for the other base class methods.

=head2 store ( $self, $id, $timeout = L</$CACHE_TIMEOUT> )

Store connection to the cache.

!!! WARNING !!! - C<on_error>, C<on_eof>, C<on_read> and C<timeout> attributes will be redefined when handle is stored. You need to restore this attributes manually after handle will be fetched from cache.

=head1 PACKAGE VARIABLES

=head2 $CACHE_TIMEOUT = 4

Defaul cache timeout is C<4>.

=head1 SEEE ALSO

L<AnyEvent::Handle>, L<AnyEvent::Socket>, L<Pcore::Proxy>

=cut
