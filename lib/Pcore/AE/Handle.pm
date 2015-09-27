package Pcore::AE::Handle;

use Pcore qw[-export];
use parent qw[AnyEvent::Handle];
use AnyEvent::Socket qw[];
use Pcore::AE::DNS::Cache;
use Pcore::HTTP::Message::Headers;
use HTTP::Parser::XS qw[HEADERS_AS_ARRAYREF HEADERS_NONE];
use Pcore::AE::Handle::Cache;
use Const::Fast qw[const];

no Pcore;

our %EXPORT_TAGS = (
    PROXY_TYPE  => [qw[$PROXY_TYPE_HTTP $PROXY_TYPE_CONNECT $PROXY_TYPE_SOCKS5 $PROXY_TYPE_SOCKS4 $PROXY_TYPE_SOCKS4A]],
    PROXY_ERROR => [qw[$PROXY_OK $PROXY_ERROR_CONNECT $PROXY_ERROR_AUTH $PROXY_ERROR_TYPE $PROXY_ERROR_OTHER]],
    PERSISTENT  => [qw[$PERSISTENT_IDENT $PERSISTENT_ANY $PERSISTENT_NO_PROXY]],
);

const our $PROXY_TYPE_HTTP    => 1;
const our $PROXY_TYPE_CONNECT => 2;
const our $PROXY_TYPE_SOCKS4  => 31;
const our $PROXY_TYPE_SOCKS4A => 32;
const our $PROXY_TYPE_SOCKS5  => 33;

const our $PROXY_OK            => 0;    # no error, connected
const our $PROXY_ERROR_CONNECT => 1;    # proxy should be disabled
const our $PROXY_ERROR_AUTH    => 2;    # proxy should be disabled
const our $PROXY_ERROR_TYPE    => 3;    # invalid proty type used, proxy type should be banned
const our $PROXY_ERROR_OTHER   => 4;    # unknown error

# $PERSISTENT_IDENT:
#     - no proxy - use cached direct connections;
#     - proxy - use cached connection through same proxy;
#     - proxy pool - use ANY cached connection from the same proxy pool;
#
# $PERSISTENT_ANY
#     - use ANY cached connection (direct or proxied);
#
# $PERSISTENT_NO_PROXY
#     - no proxy - use cached direct connections;
#     - proxy or proxy pool - do not use cache;

const our $PERSISTENT_IDENT    => 1;
const our $PERSISTENT_ANY      => 2;
const our $PERSISTENT_NO_PROXY => 3;

const our $DISABLE_PROXY => 1;

const our $CACHE => Pcore::AE::Handle::Cache->new( { default_timeout => 4 } );

# register "http_headers" push_read type
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

sub new ( $self, @ ) {
    my %args = (
        connect_timeout => 10,
        proxy           => undef,               # can be a proxy object or proxy pool object
        persistent      => $PERSISTENT_IDENT,
        session         => undef,
        @_[ 1 .. $#_ ],
    );

    # parse connect attribute
    if ( ref $args{connect} ne 'ARRAY' ) {
        my $uri = ref $args{connect} ? $args{connect} : P->uri( $args{connect}, 'tcp://' );

        $args{connect} = [ $uri->host->name, $uri->connect_port, $uri->scheme ];
    }

    # default scheme is "tcp"
    $args{connect}->[2] ||= 'tcp';

    # create connect id, "scheme_port"
    $args{connect}->[3] = $args{connect}->[2] . q[_] . $args{connect}->[1];

    if ( $args{fh} ) {
        $args{on_connect}->( $self->SUPER::new(%args), undef, undef, undef );
    }
    else {
        my $persistent = delete $args{persistent};

        my $persistent_id = {};

        $persistent_id->{any} = join q[|], $args{connect}->[2], $args{connect}->[0], $args{connect}->[1], $args{session} // q[];

        $persistent_id->{no_proxy} = join q[|], $persistent_id->{any}, 0;

        if ( $args{proxy} ) {
            if ( $args{proxy}->is_proxy_pool ) {
                $persistent_id->{proxy_pool} = join q[|], $persistent_id->{any}, 1, $args{proxy}->id;
            }
            else {
                $persistent_id->{proxy_pool} = join q[|], $persistent_id->{any}, 1, $args{proxy}->source->pool->id;

                $persistent_id->{proxy} = join q[|], $persistent_id->{any}, 2, $args{proxy}->id;
            }
        }

        # fetch persistent connection and return on success
        if ($persistent) {
            my $effective_persistent_id;

            if ( $persistent == $PERSISTENT_ANY ) {
                $effective_persistent_id = $persistent_id->{any};
            }
            elsif ( $persistent == $PERSISTENT_IDENT ) {
                if ( !$args{proxy} ) {
                    $effective_persistent_id = $persistent_id->{no_proxy};
                }
                elsif ( $args{proxy}->is_proxy_pool ) {
                    $effective_persistent_id = $persistent_id->{proxy_pool};
                }
                else {
                    $effective_persistent_id = $persistent_id->{proxy};
                }
            }
            elsif ( $persistent == $PERSISTENT_NO_PROXY ) {
                $effective_persistent_id = $persistent_id->{no_proxy};
            }
            else {
                die q[Invalid persistent value];
            }

            if ( my $h = $CACHE->fetch($effective_persistent_id) ) {
                $h->{persistent} = 1;

                $args{on_connect}->( $h, undef, undef, undef );

                return;
            }
        }

        $args{persistent} = 0;

        $args{persistent_id} = [ values $persistent_id->%* ];

        if ( my $conect_timeout = $args{connect_timeout} ) {
            my $on_prepare = $args{on_prepare};

            $args{on_prepare} = sub ($h) {
                delete $h->{on_prepare};

                $on_prepare->($h) if $on_prepare;

                return $conect_timeout;
            };
        }

        if ( !$args{proxy} ) {
            my $hdl;

            my $on_connect_error = $args{on_connect_error};
            my $on_error         = $args{on_error};
            my $on_connect       = $args{on_connect};

            $args{on_connect_error} = sub ( $h, $message ) {
                delete $h->{on_connect_error};
                delete $h->{on_connect};

                if ($on_connect_error) {
                    $on_connect_error->( $hdl, $message );
                }
                elsif ($on_error) {
                    $on_error->( $hdl, 1, $message );
                }
                else {
                    $on_connect->( undef, undef, undef, undef );
                }

                return;
            };

            $args{on_connect} = sub ( $h, @args ) {
                delete $h->{on_connect_error};
                delete $h->{on_connect};

                $on_connect->( $hdl, @args );

                return;
            };

            $hdl = $self->SUPER::new(%args);
        }
        else {
            $args{proxy}->get_slot(
                $args{connect},
                sub ( $proxy, $proxy_type ) {
                    if ( !$proxy_type ) {

                        # TODO throw error
                    }
                    else {
                        # add proxy persistent id key here, because we haven't proxy credentials before
                        push $args{persistent_id}->@*, join q[|], $persistent_id->{any}, 2, $proxy->id if $args{proxy}->is_proxy_pool;

                        $args{proxy} = $proxy;

                        $args{proxy_type} = $proxy_type;

                        $self->_connect_proxy( \%args );
                    }

                    return;
                }
            );
        }
    }

    return;
}

sub DESTROY ($self) {
    if ( ${^GLOBAL_PHASE} ne 'DESTRUCT' ) {
        $self->{proxy}->finish_thread if $self->{proxy};

        $self->SUPER::DESTROY;
    }

    return;
}

# PROXY CONNECTORS
sub _connect_proxy ( $self, $args ) {
    state $keys = [qw[on_timeout on_rtimeout on_wtimeout on_error on_eof on_read]];

    $self->_check_proxy(
        $args->{proxy},
        $args->{connect},
        sub ( $proxy, $proxy_type ) {
            my $hdl;

            my $connect                = $args->{connect};
            my $on_proxy_connect_error = delete $args->{on_proxy_connect_error};
            my $on_connect_error       = $args->{on_connect_error};
            my $on_error               = $args->{on_error};
            my $on_connect             = $args->{on_connect};

            $args->{on_connect_error} = sub ( $h, $message, $disable_proxy = 1 ) {
                delete $h->{on_connect_error};
                delete $h->{on_connect};

                $disable_proxy ? $proxy->connect_failure : $proxy->connect_ok;

                if ($on_proxy_connect_error) {
                    $on_proxy_connect_error->( $hdl, $message );
                }
                elsif ($on_connect_error) {
                    $on_connect_error->( $hdl, $message );
                }
                elsif ($on_error) {
                    $on_error->( $hdl, 1, $message );
                }
                else {
                    $on_connect->( undef, undef, undef, undef );
                }

                return;
            };

            if ( !$proxy_type ) {
                $proxy->finish_thread;

                $args->{on_connect_error}->( undef, q[Proxy doesn't support this connection type], 0 );

                return;
            }
            elsif ( $proxy_type == $PROXY_TYPE_HTTP ) {
                $args->{on_connect} = sub ( $h, @args ) {
                    delete $h->{on_connect_error};
                    delete $h->{on_connect};

                    $h->{connect} = $connect;

                    $on_connect->( $hdl, @args );
                };
            }
            else {
                my %orig_args = $args->%{ $keys->@* };
                delete $args->@{ $keys->@* };

                if ( $args->{connect_timeout} ) {
                    $orig_args{timeout}  = delete $args->{timeout};
                    $orig_args{rtimeout} = delete $args->{rtimeout};

                    $args->{timeout} = $args->{connect_timeout};
                }

                $args->{on_connect} = sub ( $h, @args ) {
                    delete $hdl->{on_connect_error};
                    delete $hdl->{on_connect};

                    $hdl->{connect} = $connect;

                    $hdl->{peername} = $connect->[0];

                    my $on_proxy_error = sub ( $h, $message, $disable_proxy = 0 ) {
                        delete $h->{on_error};

                        $h->destroy if $h;

                        $proxy->disable if $disable_proxy;

                        if ( $on_proxy_connect_error && $disable_proxy ) {
                            $on_proxy_connect_error->( $hdl, $message );
                        }
                        elsif ($on_connect_error) {
                            $on_connect_error->( $hdl, $message );
                        }
                        elsif ($on_error) {
                            $on_error->( $hdl, 1, $message );
                        }
                        else {
                            $on_connect->( undef, undef, undef, undef );
                        }

                        return;
                    };

                    $hdl->on_error(
                        sub ( $h, $fatal, $message ) {
                            $on_proxy_error->( $h, $message, 0 );

                            return;
                        }
                    );

                    my $on_proxy_connect = sub ($h) {
                        delete $h->{on_error};

                        # restore orig. callbacks
                        for my $method ( grep { $orig_args{$_} } keys %orig_args ) {
                            $h->$method( $orig_args{$method} );
                        }

                        $on_connect->( $hdl, undef, undef, undef );

                        return;
                    };

                    if ( $proxy_type == $PROXY_TYPE_CONNECT ) {
                        $hdl->_connect_proxy_connect( $proxy, $connect, $on_proxy_error, $on_proxy_connect );
                    }
                    elsif ( $proxy_type == $PROXY_TYPE_SOCKS5 ) {
                        $hdl->_connect_proxy_socks5( $proxy, $connect, $on_proxy_error, $on_proxy_connect );
                    }
                    elsif ( $proxy_type == $PROXY_TYPE_SOCKS4 || $proxy_type == $PROXY_TYPE_SOCKS4A ) {
                        $hdl->_connect_proxy_socks4( $proxy, $connect, $on_proxy_error, $on_proxy_connect );
                    }
                    else {
                        die 'Invalid proxy type, please report';
                    }

                    return;
                };
            }

            $args->{proxy_type} = $proxy_type;

            $args->{connect} = [ $args->{proxy}->host->name, $args->{proxy}->port ];

            $hdl = $self->SUPER::new( $args->%* );

            return;
        }
    );

    return;
}

sub _connect_proxy_connect ( $self, $proxy, $connect, $on_error, $on_connect ) {
    $self->push_write( q[CONNECT ] . $connect->[0] . q[:] . $connect->[1] . q[ HTTP/1.1] . $CRLF . ( $proxy->userinfo ? q[Proxy-Authorization: Basic ] . $proxy->userinfo_b64 . $CRLF : q[] ) . $CRLF );

    $self->read_http_res_headers(
        headers => 0,
        sub ( $h, $res, $error_reason ) {
            if ($error_reason) {
                $on_error->( $h, 'Invalid proxy connect response' );
            }
            else {
                if ( $res->{status} == 200 ) {
                    $on_connect->($h);
                }
                elsif ( $res->{status} == 407 ) {
                    $on_error->( $h, $res->{status} . q[ - ] . $res->{reason}, $DISABLE_PROXY );
                }
                else {
                    $on_error->( $h, $res->{status} . q[ - ] . $res->{reason} );
                }
            }

            return;
        }
    );

    return;
}

sub _connect_proxy_socks5 ( $self, $proxy, $connect, $on_error, $on_connect ) {

    # start handshake
    if ( $proxy->userinfo ) {
        $self->push_write(qq[\x05\x02\x00\x02]);
    }
    else {
        $self->push_write(qq[\x05\x01\x00]);
    }

    $self->push_read(
        chunk => 2,
        sub ( $h, $chunk ) {
            my ( $ver, $method ) = unpack 'C*', $chunk;

            if ( $method == 255 ) {    # no valid auth method was proposed
                $on_error->( $h, 'No authorization method was found', $DISABLE_PROXY );
            }
            elsif ( $method == 2 ) {    # start username / password authorization
                $h->push_write( qq[\x01] . pack( 'C', length $proxy->username ) . $proxy->username . pack( 'C', length $proxy->password ) . $proxy->password );

                $h->push_read(
                    chunk => 2,
                    sub ( $h, $chunk ) {
                        my ( $auth_ver, $auth_status ) = unpack 'C*', $chunk;

                        if ( $auth_status != 0 ) {    # auth error
                            $on_error->( $h, 'Authorization failure', $DISABLE_PROXY );
                        }
                        else {
                            $h->_socks5_establish_tunnel( $proxy, $connect, $on_error, $on_connect );
                        }

                        return;
                    }
                );
            }
            elsif ( $method == 0 ) {                  # no authorization needed
                $h->_socks5_establish_tunnel( $proxy, $connect, $on_error, $on_connect );

                return;
            }
            else {
                $on_error->( $h, 'Authorization method is not supported', $DISABLE_PROXY );
            }

            return;
        }
    );

    return;
}

sub _socks5_establish_tunnel ( $self, $proxy, $connect, $on_error, $on_connect ) {

    # detect destination addr type
    if ( my $ipn4 = AnyEvent::Socket::parse_ipv4( $connect->[0] ) ) {    # IPv4 addr
        $self->push_write( qq[\x05\x01\x00\x01] . $ipn4 . pack( 'n', $connect->[1] ) );
    }
    elsif ( my $ipn6 = AnyEvent::Socket::parse_ipv6( $connect->[0] ) ) {    # IPv6 addr
        $self->push_write( qq[\x05\x01\x00\x04] . $ipn6 . pack( 'n', $connect->[1] ) );
    }
    else {                                                                  # domain name
        $self->push_write( qq[\x05\x01\x00\x03] . pack( 'C', length $connect->[0] ) . $connect->[0] . pack( 'n', $connect->[1] ) );
    }

    $self->push_read(
        chunk => 4,
        sub ( $h, $chunk ) {
            my ( $ver, $rep, $rsv, $atyp ) = unpack( 'C*', $chunk );

            if ( $rep == 0 ) {
                if ( $atyp == 1 ) {                                         # IPv4 addr, 4 bytes
                    $h->push_read(                                          # read IPv4 addr (4 bytes) + port (2 bytes)
                        chunk => 6,
                        sub ( $h, $chunk ) {

                            # TODO validate: 4 bytes IP addr, 2 bytes port

                            $on_connect->($h);

                            return;
                        }
                    );
                }
                elsif ( $atyp == 3 ) {                                      # domain name
                    $h->push_read(                                          # read domain name length
                        chunk => 1,
                        sub ( $h, $chunk ) {
                            $h->push_read(                                  # read domain name + port (2 bytes)
                                chunk => unpack( 'C', $chunk ) + 2,
                                sub ( $h, $chunk ) {

                                    # TODO validate domain name + port

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

                            # TODO validate IPv6 + port

                            $on_connect->($h);

                            return;
                        }
                    );
                }
            }
            else {
                $on_error->( $h, q[Tunnel creation error] );
            }

            return;
        }
    );

    return;
}

sub _connect_proxy_socks4 ( $self, $proxy, $connect, $on_error, $on_connect ) {
    AnyEvent::Socket::resolve_sockaddr $connect->[0], $connect->[1], 'tcp', undef, undef, sub {
        my @target = @_;

        unless (@target) {
            $on_error->( $self, qq[Host name "$connect->[0]" couldn't be resolved] );    # not a proxy connect error

            return;
        }

        my $target = shift @target;

        $self->push_write( qq[\x04\x01] . pack( 'n', $connect->[1] ) . AnyEvent::Socket::unpack_sockaddr( $target->[3] ) . $proxy->userinfo . qq[\x00] );

        $self->push_read(
            chunk => 8,
            sub ( $h, $chunk ) {
                my $rep = unpack 'C*', substr( $chunk, 1, 1 );

                if ( $rep == 90 ) {    # request granted
                    $on_connect->($h);
                }
                elsif ( $rep == 91 ) {    # request rejected or failed, tunnel creation error
                    $on_error->( $self, 'Request rejected or failed' );
                }
                elsif ( $rep == 92 ) {    # request rejected becasue SOCKS server cannot connect to identd on the client
                    $on_error->( $self, 'Request rejected becasue SOCKS server cannot connect to identd on the client', $DISABLE_PROXY );
                }
                elsif ( $rep == 93 ) {    # request rejected because the client program and identd report different user-ids
                    $on_error->( $self, 'Request rejected because the client program and identd report different user-ids', $DISABLE_PROXY );
                }
                else {                    # unknown error
                    $on_error->( $self, 'Invalid socks4 server response', $DISABLE_PROXY );
                }

                return;
            }
        );

        return;
    };

    return;
}

# READERS
sub read_http_res_headers {
    my $self = shift;
    my $cb   = pop;
    my %args = (
        headers  => 0,    # true - create new headers obj, false - do not parse headers, ref - headers obj to add headers to
        trailing => 0,    # read trailing headers, mandatory if trailing headers are expected
        @_,
    );

    $self->push_read(
        http_headers => sub ( $h, @ ) {
            if ( $_[1] ) {
                my $res;

                # $len = -1 - incomplete headers, -2 - errors, >= 0 - headers length
                ( my $len, $res->{minor_version}, $res->{status}, $res->{reason}, my $headers_arr ) = HTTP::Parser::XS::parse_http_response( $args{trailing} ? 'HTTP/1.1 200 OK' . $CRLF . $_[1] : $_[1], !$args{headers} ? HEADERS_NONE : HEADERS_AS_ARRAYREF );

                if ( $len == -1 ) {
                    $cb->( $h, undef, q[Headers are incomplete] );
                }
                elsif ( $len == -2 ) {
                    $cb->( $h, undef, q[Headers are corrupt] );
                }
                else {
                    if ( $args{headers} ) {
                        $res->{headers} = ref $args{headers} ? $args{headers} : Pcore::HTTP::Message::Headers->new;

                        # repack received headers to the standard format
                        for ( my $i = 0; $i <= $headers_arr->$#*; $i += 2 ) {
                            $headers_arr->[$i] = uc $headers_arr->[$i] =~ tr/-/_/r;
                        }

                        $res->{headers}->add($headers_arr);
                    }

                    $cb->( $h, $res, undef );
                }
            }
            elsif ( $args{trailing} ) {    # trailing headers can be empty, this is not an error
                $cb->( $h, undef, undef );
            }
            else {
                $cb->( $h, undef, q[No headers] );
            }

            return;
        }
    );

    return;
}

sub read_http_req_headers ( $self, $cb ) {
    $self->push_read(
        http_headers => sub ( $h, @ ) {
            if ( $_[1] ) {
                my $env = {};

                my $res = HTTP::Parser::XS::parse_http_request( $_[1], $env );

                if ( $res == -1 ) {
                    $cb->( $h, undef, 'Request is corrupt' );
                }
                elsif ( $res == -2 ) {
                    $cb->( $h, undef, 'Request is incomplete' );
                }
                else {
                    $cb->( $h, $env, undef );
                }
            }
            else {
                $cb->( $h, undef, 'No headers' );
            }

            return;
        }
    );

    return;
}

sub read_http_body ( $self, $on_read, @ ) {
    my %args = (
        chunked  => 0,
        length   => undef,    # false - read until EOF
        headers  => 0,
        buf_size => 65_536,
        @_[ 2 .. $#_ ],
    );

    my $on_read_buf = sub ( $buf_ref, $error_message ) {
        state $buf = q[];

        state $total_bytes_readed = 0;

        if ($error_message) {

            # drop buffer if has data
            return if length $buf && !$on_read->( $self, \$buf, $total_bytes_readed, undef );

            # throw error
            $on_read->( $self, undef, $total_bytes_readed, $error_message );
        }
        elsif ( defined $buf_ref ) {
            $buf .= $buf_ref->$*;

            $total_bytes_readed += length $buf_ref->$*;

            if ( length $buf > $args{buf_size} ) {
                my $continue = $on_read->( $self, \$buf, $total_bytes_readed, undef );

                $buf = q[];

                return $continue ? $total_bytes_readed : 0;
            }
            else {
                return $total_bytes_readed;
            }
        }
        else {
            # drop buffer if has data
            return if length $buf && !$on_read->( $self, \$buf, $total_bytes_readed, undef );

            $on_read->( $self, undef, $total_bytes_readed, undef );
        }

        return;
    };

    # TODO rewrite chunk reader using single on_read callback
    if ( $args{chunked} ) {    # read chunked body
        my $read_chunk;

        $read_chunk = sub ( $h, @ ) {
            my $chunk_len_ref = \$_[1];

            if ( $chunk_len_ref->$* =~ /\A([[:xdigit:]]+)\z/sm ) {    # valid chunk length
                my $chunk_len = hex $1;

                if ($chunk_len) {                                     # read chunk body
                    $h->push_read(
                        chunk => $chunk_len,
                        sub ( $h, @ ) {
                            my $chunk_ref = \$_[1];

                            if ( !$on_read_buf->( $chunk_ref, undef ) ) {    # transfer was cancelled by "on_body" call
                                undef $read_chunk;

                                return;
                            }
                            else {
                                # read trailing chunk $CRLF
                                $h->push_read(
                                    line => sub ( $h, @ ) {
                                        if ( length $_[1] ) {                # error, chunk traililg can contain only $CRLF
                                            undef $read_chunk;

                                            $on_read_buf->( undef, 'Garbled chunked transfer encoding' );
                                        }
                                        else {
                                            $h->push_read( line => $read_chunk );
                                        }

                                        return;
                                    }
                                );
                            }

                            return;
                        }
                    );
                }
                else {    # last chunk

                    # read trailing headers
                    $h->read_http_res_headers(
                        headers  => $args{headers},
                        trailing => 1,
                        sub ( $h, $res, $error_reason ) {
                            undef $read_chunk;

                            if ($error_reason) {
                                $on_read_buf->( undef, 'Garbled chunked transfer encoding (invalid trailing headers)' );
                            }
                            else {
                                $on_read_buf->( undef, undef );
                            }

                            return;
                        }
                    );
                }
            }
            else {    # invalid chunk length
                undef $read_chunk;

                $on_read_buf->( undef, 'Garbled chunked transfer encoding' );
            }

            return;
        };

        $self->push_read( line => $read_chunk );
    }
    elsif ( !$args{length} ) {    # read until EOF
        $self->on_eof(
            sub ($h) {

                # remove "on_read" callback
                $h->on_read(undef);

                # remove "on_eof" callback
                $h->on_eof(undef);

                $on_read_buf->( undef, undef );

                return;
            }
        );

        $self->on_read(
            sub ($h) {
                my $total_bytes_readed = $on_read->( \delete $h->{rbuf}, undef );

                if ( !$total_bytes_readed ) {

                    # remove "on_read" callback
                    $h->on_read(undef);

                    # remove "on_eof" callback
                    $h->on_eof(undef);
                }

                return;
            }
        );
    }
    else {    # read body with known length
        $self->on_read(
            sub ($h) {
                my $total_bytes_readed = $on_read_buf->( \delete $h->{rbuf}, undef );

                if ( !$total_bytes_readed ) {

                    # remove "on_read" callback
                    $h->on_read(undef);
                }
                else {
                    if ( $total_bytes_readed == $args{length} ) {

                        # remove "on_read" callback
                        $h->on_read(undef);

                        $on_read_buf->( undef, undef );
                    }
                    elsif ( $total_bytes_readed > $args{length} ) {

                        # remove "on_read" callback
                        $h->on_read(undef);

                        $on_read_buf->( undef, q[Readed body length is larger than expected] );
                    }
                }

                return;
            }
        );
    }

    return;
}

sub read_eof ( $self, $on_read ) {
    $self->read_http_body( $on_read, chunked => 0, length => undef );

    return;
}

# CACHE METHODS
sub store ( $self, $timeout = undef ) {
    $CACHE->store( $self, $timeout );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitExcessComplexity                                                                          │
## │      │ 78                   │ * Subroutine "new" with high complexity score (28)                                                             │
## │      │ 247                  │ * Subroutine "_connect_proxy" with high complexity score (23)                                                  │
## │      │ 679                  │ * Subroutine "read_http_body" with high complexity score (29)                                                  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 159, 385             │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 394, 422, 475, 552   │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 63, 426, 429, 441,   │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## │      │ 479, 482, 485, 564   │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 626                  │ ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │                      │ Documentation::RequirePodLinksIncludeText                                                                      │
## │      │ 919                  │ * Link L<AnyEvent::Handle> on line 925 does not specify text                                                   │
## │      │ 919                  │ * Link L<AnyEvent::Handle> on line 933 does not specify text                                                   │
## │      │ 919                  │ * Link L<AnyEvent::Handle> on line 961 does not specify text                                                   │
## │      │ 919                  │ * Link L<AnyEvent::Handle> on line 977 does not specify text                                                   │
## │      │ 919                  │ * Link L<AnyEvent::Socket> on line 977 does not specify text                                                   │
## │      │ 919, 919             │ * Link L<Pcore::Proxy> on line 943 does not specify text                                                       │
## │      │ 919                  │ * Link L<Pcore::Proxy> on line 977 does not specify text                                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 59, 64, 479, 482,    │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## │      │ 485, 491, 569        │                                                                                                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Handle - L<AnyEvent::Handle> subclass with proxy support

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
