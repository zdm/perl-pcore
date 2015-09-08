package Pcore::AnyEvent::Handle;

use Pcore;
use parent qw[AnyEvent::Handle];
use AnyEvent::Socket qw[];
use Pcore::Proxy;
use Pcore::HTTP::Message::Headers;
use HTTP::Parser::XS qw[HEADERS_AS_ARRAYREF HEADERS_NONE];
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
const our $PROXY_TYPE_SOCKS4A => 5;
const our $PROXY_TYPE_HTTP    => 6;

const our $PROXY_TYPE_SCHEME => {
    connect => $PROXY_TYPE_CONNECT,
    https   => $PROXY_TYPE_HTTPS,
    socks5  => $PROXY_TYPE_SOCKS5,
    socks4  => $PROXY_TYPE_SOCKS4,
    socks4a => $PROXY_TYPE_SOCKS4A,
    http    => $PROXY_TYPE_HTTP,
};

our $CACHE = {};

# default cache timeout
our $CACHE_TIMEOUT = 4;

AnyEvent::Handle::register_read_type http_headers => sub ( $self, $cb ) {
    return sub {
        return unless defined $_[0]{rbuf};

        if ( ( my $idx_crlf = index $_[0]{rbuf}, $CRLF ) >= 0 ) {
            if ( $idx_crlf == 0 ) {    # first line is empty, no headers, used to read possible trailing headers
                $cb->( $_[0], substr( $_[0]{rbuf}, 0, 2, q[] ) );

                return 1;
            }
            elsif ( ( my $idx = index $_[0]{rbuf}, qq[\x0A\x0D\x0A] ) >= 0 ) {
                $cb->( $_[0], substr( $_[0]{rbuf}, 0, $idx + 3, q[] ) );

                return 1;
            }
            else {
                return;
            }
        }
        else {
            return;
        }
    };
};

sub new ( $self, %args ) {

    # make copy to prevent memory leaks
    my %args_orig = %args;

    if ( $args{connect_timeout} ) {
        $args{on_prepare} = sub ($h) {
            $args_orig{on_prepare}->($h) if $args_orig{on_prepare};

            return $args_orig{connect_timeout};
        };
    }

    if ( !$args{fh} && $args{proxy} ) {
        $args{proxy} = Pcore::Proxy->new( $args{proxy} ) if !ref $args{proxy};

        # automatically select proxy type
        if ( !$args{proxy_type} ) {

            if ( $args{connect}->[1] == 443 ) {
                $args{proxy_type} = $args{proxy}->is_https || $args{proxy}->is_socks5 || $args{proxy}->is_http;
            }
            else {
                $args{proxy_type} = $args{proxy}->is_connect || $args{proxy}->is_socks5 || $args{proxy}->is_http;
            }
        }

        # try to detect proxy type by scheme
        $args{proxy_type} = $PROXY_TYPE_SCHEME->{ $args{proxy}->scheme } if !$args{proxy_type} && $args{proxy}->scheme && exists $PROXY_TYPE_SCHEME->{ $args{proxy}->scheme };

        # redefine "connect"
        $args{connect} = [ $args{proxy}->host->name, $args{proxy}->port ];

        # redefine "on_connect_error"
        my $on_connect_error = sub ( $h, $message, $error_type ) {
            $h->destroy if $h;

            if ( $args_orig{on_proxy_connect_error} and $error_type != $CONNECT_ERROR ) {
                $args_orig{on_proxy_connect_error}->( $h, $message, $error_type == $PROXY_CONNECT_ERROR ? 1 : 0 );
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

        $args{on_connect_error} = sub ( $h, $message, $error_type = $PROXY_CONNECT_ERROR ) {
            $on_connect_error->( $h, $message, $error_type );

            return;
        };

        if ( !$args{proxy_type} ) {
            $on_connect_error->( undef, 'Invalid proxy type', $PROXY_CONNECT_ERROR );

            return;
        }
        elsif ( $args{proxy_type} == $PROXY_TYPE_SOCKS4 or $args{proxy_type} == $PROXY_TYPE_SOCKS4A ) {
            $on_connect_error->( undef, 'Proxy type is not supported', $PROXY_CONNECT_ERROR );

            return;
        }
        elsif ( $args{proxy_type} == $PROXY_TYPE_SOCKS5 or $args{proxy_type} == $PROXY_TYPE_CONNECT or $args{proxy_type} = $PROXY_TYPE_HTTPS ) {
            $args{timeout} = $args{connect_timeout} if $args{connect_timeout};

            # all proxy connection timeouts will be handled by "on_error" callback
            delete $args{on_timeout};

            # redefine "on_error" to handle proxy connection errors
            # by default all errors - are proxy connect errors
            $args{on_error} = sub ( $h, $fatal, $message ) {
                $h->{on_connect_error}->( $h, $message, $PROXY_HANDSHAKE_ERROR );

                return;
            };

            # redefine "on_connect"
            $args{on_connect} = sub ( $h, $host, $port, $retry ) {
                my $on_connect = sub ($h) {

                    # restore orig. settings
                    $h->timeout( $args_orig{timeout} );

                    # restore orig. callbacks
                    $h->on_timeout( $args_orig{on_timeout} );

                    $h->on_error( $args_orig{on_error} );

                    # call orig "on_connect" cb
                    $args_orig{on_connect}->( $h, $host, $port, $retry ) if $args_orig{on_connect};

                    return;
                };

                # convert host to the punycode, if needed
                $args_orig{connect}->[0] = P->host( $args_orig{connect}->[0] )->name if utf8::is_utf8( $args_orig{connect}->[0] );

                if ( $h->{proxy_type} == $PROXY_TYPE_SOCKS5 ) {
                    _connect_socks5_proxy( $h, $h->{proxy}, $args_orig{connect}, $on_connect, $on_connect_error );
                }
                elsif ( $h->{proxy_type} == $PROXY_TYPE_CONNECT or $h->{proxy_type} == $PROXY_TYPE_HTTPS ) {
                    _connect_connect_proxy( $h, $h->{proxy}, $args_orig{connect}, $on_connect, $on_connect_error );
                }

                return;
            };
        }
    }

    return $self->SUPER::new(%args);
}

sub read_http_headers {
    my $cb = pop;
    my ( $self, $headers, $trailing ) = @_;

    # headers:
    # undef - new object will be created
    # ref - use this object
    # 0 - do not parse headers

    $self->push_read(
        http_headers => sub ( $h, @ ) {
            my $res;

            if ( $_[1] ) {

                # $len = -1 - incomplete headers, -2 - errors, >= 0 - headers length
                ( my $len, $res->{minor_version}, $res->{status}, $res->{reason}, my $headers_arr ) = HTTP::Parser::XS::parse_http_response( $trailing ? 'HTTP/1.1 200 OK' . $CRLF . $_[1] : $_[1], defined $headers && $headers == 0 ? HEADERS_NONE : HEADERS_AS_ARRAYREF );

                if ( $len > 0 ) {
                    $headers //= Pcore::HTTP::Message::Headers->new;

                    if ($headers) {

                        # repack received headers to the standard format
                        for ( my $i = 0; $i <= $headers_arr->$#*; $i += 2 ) {
                            $headers_arr->[$i] = uc $headers_arr->[$i] =~ tr/-/_/r;
                        }

                        $res->{headers} = $headers;

                        $res->{headers}->add($headers_arr);
                    }
                }
                else {
                    undef $res;
                }
            }
            elsif ($trailing) {    # trailing headers can be empty, this is not an error
                $res = {};
            }

            $cb->( $h, $res );

            return;
        }
    );

    return;
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
                                        $on_connect->($h);

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
                                                $on_connect->($h);

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
                                        $on_connect->($h);

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

    # TODO how to clarify, what this timeout means, proxy not respond or tunnel creation timeout (target server not respond)?
    # currently we assume, that this is NOT THE PROXY CONNECTION ERROR
    $h->on_error(
        sub($h, $fatal, $message) {
            $on_connect_error->( $h, $message, $CONNECT_ERROR );

            return;
        }
    );

    $h->push_write( q[CONNECT ] . $connect->[0] . q[:] . $connect->[1] . q[ HTTP/1.1] . $CRLF . ( $proxy->userinfo ? q[Proxy-Authorization: Basic ] . $proxy->userinfo_b64 . $CRLF : $CRLF ) . $CRLF );

    $h->read_http_headers(
        0,
        sub ( $h, $res ) {
            if ( !$res ) {
                $on_connect_error->( $h, q[Invalid proxy connect response], $PROXY_HANDSHAKE_ERROR );
            }
            else {
                if ( $res->{status} == 200 ) {
                    $on_connect->($h);
                }
                elsif ( $res->{status} == 503 ) {    # error creating tunnel
                    $on_connect_error->( $h, $res->{status} . q[ - ] . $res->{reason}, $CONNECT_ERROR );
                }
                else {
                    $on_connect_error->( $h, $res->{status} . q[ - ] . $res->{reason}, $PROXY_HANDSHAKE_ERROR );
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
## │    3 │ 64                   │ Subroutines::ProhibitExcessComplexity - Subroutine "new" with high complexity score (35)                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 321, 435             │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 49, 325, 328, 355,   │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## │      │ 358, 361             │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 207, 251             │ ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │                      │ Documentation::RequirePodLinksIncludeText                                                                      │
## │      │ 505                  │ * Link L<AnyEvent::Handle> on line 511 does not specify text                                                   │
## │      │ 505                  │ * Link L<AnyEvent::Handle> on line 519 does not specify text                                                   │
## │      │ 505                  │ * Link L<AnyEvent::Handle> on line 547 does not specify text                                                   │
## │      │ 505                  │ * Link L<AnyEvent::Handle> on line 563 does not specify text                                                   │
## │      │ 505                  │ * Link L<AnyEvent::Socket> on line 563 does not specify text                                                   │
## │      │ 505, 505             │ * Link L<Pcore::Proxy> on line 529 does not specify text                                                       │
## │      │ 505                  │ * Link L<Pcore::Proxy> on line 563 does not specify text                                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 45, 50, 355, 358,    │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## │      │ 361, 375             │                                                                                                                │
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
