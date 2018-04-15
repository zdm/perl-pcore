package Pcore::API::Proxy;

use Pcore -const, -class, -res, -export => { PROXY_TYPE => [qw[$PROXY_TYPE_HTTP $PROXY_TYPE_CONNECT $PROXY_TYPE_SOCKS]] };
use Pcore::Util::Scalar qw[is_ref];

has uri => ( is => 'ro', isa => Str | InstanceOf ['Pcore::Util::URI'], required => 1 );

has pool => ( is => 'ro', isa => Maybe [Object] );

has threads => ( is => 'ro', isa => PositiveOrZeroInt, default => 0, init_arg => undef );

const our $PROXY_TYPE_HTTP    => 1;
const our $PROXY_TYPE_CONNECT => 2;
const our $PROXY_TYPE_SOCKS   => 3;

around new => sub ( $orig, $self, $uri ) {
    $uri = P->uri($uri) if !is_ref $uri;

    return $self->$orig( { uri => $uri } );
};

sub connect ( $self, $uri, @args ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    $uri = P->uri($uri) if !is_ref $uri;

    if ( $uri->is_http ) {
        if ( $uri->is_secure ) {
            return $self->connect_https( $uri, @args );
        }
        else {
            return $self->connect_http( $uri, @args );
        }
    }
    else {
        return $self->connect_socks( $uri, @args );
    }
}

sub connect_http ( $self, $uri, @args ) {
    my $cb = pop @args;

    $uri = P->uri($uri) if !is_ref $uri;

    $self->start_thread;

    Pcore::AE::Handle->new(
        connect => $self->{uri},
        @args,

        # connect_timeout  => $args->{connect_timeout},
        # timeout          => $args->{timeout},
        # tls_ctx          => $args->{tls_ctx},
        # bind_ip          => $args->{bind_ip},

        on_connect_error => sub ( $h, $reason ) {
            $self->finish_thread;

            $cb->( undef, res [ 600, $reason ] );

            return;
        },
        on_connect => sub ( $h, $host, $port, $retry ) {
            $h->{proxy}      = $self;
            $h->{proxy_type} = $PROXY_TYPE_HTTP;

            $h->starttls('connect') if $self->{uri}->is_secure;

            $cb->( $h, res 200 );

            return;
        },
    );

    return;
}

sub connect_https ( $self, $uri, @args ) {
    my $cb = pop @args;

    $uri = P->uri($uri) if !is_ref $uri;

    $self->start_thread;

    Pcore::AE::Handle->new(
        connect => $self->{uri},
        @args,

        # connect_timeout  => $args->{connect_timeout},
        # timeout          => $args->{timeout},
        # tls_ctx          => $args->{tls_ctx},
        # bind_ip          => $args->{bind_ip},

        on_connect_error => sub ( $h, $reason ) {
            $self->finish_thread;

            $cb->( undef, res [ 600, $reason ] );

            return;
        },
        on_connect => sub ( $h, $host, $port, $retry ) {
            $h->starttls('connect') if $self->{uri}->is_secure;

            my $buf = 'CONNECT ' . $uri->hostport . q[ HTTP/1.1] . $CRLF;

            $buf .= 'Proxy-Authorization: Basic ' . $self->{uri}->userinfo_b64 . $CRLF if $self->{uri}->userinfo;

            $buf .= $CRLF;

            $h->push_write($buf);

            $h->read_http_res_headers(
                headers => 0,
                sub ( $h1, $res, $error_reason ) {
                    if ($error_reason) {
                        $self->finish_thread;

                        $cb->( undef, res [ 600, 'Invalid proxy connect response' ] );
                    }
                    else {
                        if ( $res->{status} == 200 ) {
                            $h->{proxy}      = $self;
                            $h->{proxy_type} = $PROXY_TYPE_CONNECT;
                            $h->{peername}   = $uri->host;

                            $cb->( $h, res 200 );
                        }
                        else {
                            $self->finish_thread;

                            $cb->( undef, res [ $res->{status}, $res->{reason} ] );
                        }
                    }

                    return;
                }
            );

            return;
        },
    );

    return;
}

sub connect_socks ( $self, $uri, @args ) {
    $uri = P->uri($uri) if !is_ref $uri;

    return;
}

sub start_thread ($self) {
    $self->{threads}++;

    $self->{pool}->start_thread($self) if defined $self->{pool};

    return;
}

sub finish_thread ($self) {
    $self->{threads}--;

    $self->{pool}->finish_thread($self) if defined $self->{pool};

    return;
}

# ----------------------------------------------------------

# sub _connect_proxy_socks4 ( $self, $proxy, $connect, $on_finish ) {
#     AnyEvent::Socket::resolve_sockaddr $connect->[0], $connect->[1], 'tcp', undef, undef, sub {
#         my @target = @_;
#
#         unless (@target) {
#             $on_finish->( $self, qq[Host name "$connect->[0]" couldn't be resolved], $PROXY_ERROR_OTHER );    # not a proxy connect error
#
#             return;
#         }
#
#         my $target = shift @target;
#
#         $self->push_write( qq[\x04\x01] . pack( 'n', $connect->[1] ) . AnyEvent::Socket::unpack_sockaddr( $target->[3] ) . $proxy->userinfo . qq[\x00] );
#
#         $self->unshift_read(
#             chunk => 8,
#             sub ( $h, $chunk ) {
#                 my $rep = unpack 'C*', substr( $chunk, 1, 1 );
#
#                 # request granted
#                 if ( $rep == 90 ) {
#                     $on_finish->( $h, undef, undef );
#                 }
#
#                 # request rejected or failed, tunnel creation error
#                 elsif ( $rep == 91 ) {
#                     $on_finish->( $h, 'Request rejected or failed', $PROXY_ERROR_OTHER );
#                 }
#
#                 # request rejected becasue SOCKS server cannot connect to identd on the client
#                 elsif ( $rep == 92 ) {
#                     $on_finish->( $h, 'Request rejected becasue SOCKS server cannot connect to identd on the client', $PROXY_ERROR_AUTH );
#                 }
#
#                 # request rejected because the client program and identd report different user-ids
#                 elsif ( $rep == 93 ) {
#                     $on_finish->( $h, 'Request rejected because the client program and identd report different user-ids', $PROXY_ERROR_AUTH );
#                 }
#
#                 # unknown error or not SOCKS4 proxy response
#                 else {
#                     $on_finish->( $h, 'Invalid socks4 server response', $PROXY_ERROR_OTHER );
#                 }
#
#                 return;
#             }
#         );
#
#         return;
#     };
#
#     return;
# }
#
# sub _connect_proxy_socks5 ( $self, $proxy, $connect, $on_finish ) {
#
#     # start handshake
#     # no authentication or authenticate with username/password
#     if ( $proxy->userinfo ) {
#         $self->push_write(qq[\x05\x02\x00\x02]);
#     }
#
#     # no authentication
#     else {
#         $self->push_write(qq[\x05\x01\x00]);
#     }
#
#     $self->unshift_read(
#         chunk => 2,
#         sub ( $h, $chunk ) {
#             my ( $ver, $auth_method ) = unpack 'C*', $chunk;
#
#             # no valid authentication method was proposed
#             if ( $auth_method == 255 ) {
#                 $on_finish->( $h, 'No authentication method was found', $PROXY_ERROR_AUTH );
#             }
#
#             # start username / password authentication
#             elsif ( $auth_method == 2 ) {
#
#                 # send authentication credentials
#                 $h->push_write( qq[\x01] . pack( 'C', length $proxy->username ) . $proxy->username . pack( 'C', length $proxy->password ) . $proxy->password );
#
#                 # read authentication response
#                 $h->unshift_read(
#                     chunk => 2,
#                     sub ( $h, $chunk ) {
#                         my ( $auth_ver, $auth_status ) = unpack 'C*', $chunk;
#
#                         # authentication error
#                         if ( $auth_status != 0 ) {
#                             $on_finish->( $h, 'Authentication failure', $PROXY_ERROR_AUTH );
#                         }
#
#                         # authenticated
#                         else {
#                             _socks5_establish_tunnel( $h, $proxy, $connect, $on_finish );
#                         }
#
#                         return;
#                     }
#                 );
#             }
#
#             # no authentication is needed
#             elsif ( $auth_method == 0 ) {
#                 _socks5_establish_tunnel( $h, $proxy, $connect, $on_finish );
#
#                 return;
#             }
#
#             # unknown authentication method or not SOCKS5 response
#             else {
#                 $on_finish->( $h, 'Authentication method is not supported', $PROXY_ERROR_OTHER );
#             }
#
#             return;
#         }
#     );
#
#     return;
# }
#
# sub _socks5_establish_tunnel ( $self, $proxy, $connect, $on_finish ) {
#
#     # detect destination addr type
#     if ( my $ipn4 = AnyEvent::Socket::parse_ipv4( $connect->[0] ) ) {    # IPv4 addr
#         $self->push_write( qq[\x05\x01\x00\x01] . $ipn4 . pack( 'n', $connect->[1] ) );
#     }
#     elsif ( my $ipn6 = AnyEvent::Socket::parse_ipv6( $connect->[0] ) ) {    # IPv6 addr
#         $self->push_write( qq[\x05\x01\x00\x04] . $ipn6 . pack( 'n', $connect->[1] ) );
#     }
#     else {                                                                  # domain name
#         $self->push_write( qq[\x05\x01\x00\x03] . pack( 'C', length $connect->[0] ) . $connect->[0] . pack( 'n', $connect->[1] ) );
#     }
#
#     $self->unshift_read(
#         chunk => 4,
#         sub ( $h, $chunk ) {
#             my ( $ver, $rep, $rsv, $atyp ) = unpack( 'C*', $chunk );
#
#             if ( $rep == 0 ) {
#                 if ( $atyp == 1 ) {                                         # IPv4 addr, 4 bytes
#                     $h->unshift_read(                                       # read IPv4 addr (4 bytes) + port (2 bytes)
#                         chunk => 6,
#                         sub ( $h, $chunk ) {
#                             $on_finish->( $h, undef, undef );
#
#                             return;
#                         }
#                     );
#                 }
#                 elsif ( $atyp == 3 ) {                                      # domain name
#                     $h->unshift_read(                                       # read domain name length
#                         chunk => 1,
#                         sub ( $h, $chunk ) {
#                             $h->unshift_read(                               # read domain name + port (2 bytes)
#                                 chunk => unpack( 'C', $chunk ) + 2,
#                                 sub ( $h, $chunk ) {
#                                     $on_finish->( $h, undef, undef );
#
#                                     return;
#                                 }
#                             );
#
#                             return;
#                         }
#                     );
#                 }
#                 if ( $atyp == 4 ) {    # IPv6 addr, 16 bytes
#                     $h->unshift_read(    # read IPv6 addr (16 bytes) + port (2 bytes)
#                         chunk => 18,
#                         sub ( $h, $chunk ) {
#                             $on_finish->( $h, undef, undef );
#
#                             return;
#                         }
#                     );
#                 }
#             }
#             else {
#                 $on_finish->( $h, q[Tunnel creation error], $PROXY_ERROR_OTHER );
#             }
#
#             return;
#         }
#     );
#
#     return;
# }

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Proxy

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
