package Pcore::AE::Handle::ProxyPool::Proxy;

use Pcore qw[-class];
use Pcore::AE::Handle::ProxyPool::Proxy::Removed;
use Pcore::AE::Handle;
use Pcore::AE::Handle::Const qw[:PROXY_TYPE];
use Const::Fast qw[const];

extends qw[Pcore::Util::URI];

has source => ( is => 'ro', isa => ConsumerOf ['Pcore::AE::Handle::ProxyPool::Source'], required => 1, weak_ref => 1 );

has id      => ( is => 'lazy', isa => Str, init_arg => undef );
has pool_id => ( is => 'ro',   isa => Int, init_arg => undef );

has removed => ( is => 'ro', default => 0, init_arg => undef );
has enabled => ( is => 'ro', default => 1, init_arg => undef );

has test_connection => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );
has test_scheme     => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

has enable_try     => ( is => 'ro', isa => Int, default => 0, init_arg => undef );
has connect_errors => ( is => 'ro', isa => Int, default => 0, init_arg => undef );

around new => sub ( $orig, $self, $uri, $source ) {
    if ( my $args = $self->_parse_uri($uri) ) {
        $args->{source} = $source;

        $self->$orig($args);
    }
    else {
        return;
    }
};

no Pcore;

const our $CHECK_SCHEME => {
    tcp => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS4, $PROXY_TYPE_SOCKS5 ] ],    # default scheme
    udp => [ [$PROXY_TYPE_SOCKS5] ],
    http  => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS4, $PROXY_TYPE_SOCKS5, $PROXY_TYPE_HTTP ], [ 'www.google.com', 80 ],  \&_test_scheme_httpx, ],
    https => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS4, $PROXY_TYPE_SOCKS5, $PROXY_TYPE_HTTP ], [ 'www.google.com', 443 ], \&_test_scheme_httpx, ],
    whois => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS4, $PROXY_TYPE_SOCKS5 ], [ 'whois.iana.org', 43 ], \&_test_whois, ],
};

sub _parse_uri ( $self, $uri ) {
    $uri = q[//] . $uri if index( $uri, q[//] ) == -1;

    my $args = $self->_parse_uri_string($uri);

    if ( $args->{authority} ) {

        # parse userinfo
        my @token = split /:/sm, $args->{authority};

        if ( @token < 2 ) {

            # port should be specified
            return;
        }
        elsif ( @token == 4 ) {

            # host:port:username:password
            $args->{authority} = $token[2] . q[:] . $token[3] . q[@] . $token[0] . q[:] . $token[1];
        }
        elsif ( @token > 4 ) {
            return;
        }

        return $args;
    }
    else {
        return;
    }
}

sub _build_id ($self) {
    return $self->hostport;
}

# TODO remove from ban lists
sub remove ($self) {
    state $q1 = $self->source->pool->dbh->query('DELETE FROM `proxy` WHERE `pool_id` = ?');

    $q1->do( bind => [ $self->pool_id ] );

    delete $self->source->pool->list->{ $self->id };

    # TODO remove from ban lists

    $self->%* = (
        removed => 1,
        enabled => 0,
    );

    bless $self, 'Pcore::AE::Handle::ProxyPool::Proxy::Removed';

    return;
}

sub disable ( $self, $timeout = undef ) {
    return if !$self->{enabled};

    $self->{enabled} = 0;

    state $q1 = $self->source->pool->dbh->query('UPDATE `proxy` SET `enabled` = 0, `enable_ts` = ? WHERE `pool_id` = ?');

    $self->{enable_ts} = time + ( $timeout // $self->source->pool->disable_timeout );

    $q1->do( bind => [ $self->{enable_ts}, $self->pool_id ] );

    return;
}

sub enable ($self) {
    return if $self->{is_enabled};

    $self->{is_enabled} = 1;

    state $q1 = $self->source->pool->dbh->query('UPDATE `proxy` SET `enabled` = 1 WHERE `pool_id` = ?');

    $q1->do( bind => [ $self->pool_id ] );

    return;
}

sub ban ( $self, $key, $timeout = undef ) {
    return;
}

# CONNECT METHODS
sub connect_ok ($self) {
    $self->{connect_errors} = 0;

    return;
}

sub connect_error ($self) {
    return if !$self->{enabled};

    $self->{connect_errors}++;

    if ( $self->{connect_errors} >= $self->source->pool->max_connect_errors ) {
        $self->remove;
    }
    else {
        $self->disable;
    }

    return;
}

# THREADS
# TODO wait for proxy
sub start_thread ( $self, $cb ) {
    $self->{threads}++;

    $cb->($self);

    return;
}

sub finish_thread ($self) {
    $self->{threads}--;

    return;
}

# CHECK PROXY
sub check ( $self, $connect, $cb ) {
    state $callback = {};

    $connect->[3] = $connect->[2] . q[:] . $connect->[1];

    my $cache_key = $self->id . q[-] . $connect->[3];

    push $callback->{$cache_key}->@*, $cb;

    return if $callback->{$cache_key}->@* > 1;

    my $proxy_type = $self->{test_connection}->{ $connect->[3] };

    if ( defined $proxy_type ) {    # proxy already checked
        while ( my $cb = shift $callback->{$cache_key}->@* ) {
            $cb->($proxy_type);
        }

        delete $callback->{$cache_key};
    }
    else {                          # run proxy check
        my @types = $CHECK_SCHEME->{ $connect->[2] }->[0]->@*;

        my $test = sub ($proxy_type) {
            if ( !$proxy_type ) {
                if ( $self->is_enabled && ( $proxy_type = shift @types ) ) {
                    if ( $proxy_type == $PROXY_TYPE_HTTP ) {
                        $self->_check_http( $proxy_type, $connect, __SUB__ );
                    }
                    else {
                        $self->_check_tunnel( $proxy_type, $connect, __SUB__ );
                    }
                }
                else {
                    $self->{test_connection}->{ $connect->[3] } = 0;    # no proxy type found

                    while ( my $cb = shift $callback->{$cache_key}->@* ) {
                        $cb->(0);
                    }

                    delete $callback->{$cache_key};
                }
            }
            else {
                $self->{test_connection}->{ $connect->[3] } = $proxy_type;    # cache connection test result

                while ( my $cb = shift $callback->{$cache_key}->@* ) {
                    $cb->($proxy_type);
                }

                delete $callback->{$cache_key};
            }
        };

        $test->(undef);
    }

    return;
}

sub _check_http ( $self, $proxy_type, $connect, $cb ) {
    $self->_test_scheme(
        $connect->[2],
        $proxy_type,
        sub ($scheme_ok) {
            unless ($scheme_ok) {    # scheme test failed
                $cb->(0);
            }
            else {                   # scheme test passed
                $cb->($proxy_type);
            }

            return;
        }
    );

    return;
}

sub _check_tunnel ( $self, $proxy_type, $connect, $cb ) {
    $self->_test_scheme(
        $connect->[2],
        $proxy_type,
        sub ($scheme_ok) {
            unless ($scheme_ok) {    # scheme test failed
                $cb->(0);
            }
            else {                   # scheme test passed

                # scheme was really tested
                # but connect port is differ from default scheme test port
                # need to test tunnel creation to the non-standard port separately
                if ( $CHECK_SCHEME->{ $connect->[2] }->[2] && $CHECK_SCHEME->{ $connect->[2] }->[1]->[1] != $connect->[1] ) {
                    $self->_test_connection(
                        $connect,
                        $proxy_type,
                        sub ($h) {
                            if ($h) {    # tunnel creation ok
                                $cb->($proxy_type);
                            }
                            else {       # tunnel creation failed
                                $cb->(0);
                            }

                            return;
                        }
                    );
                }
                else {
                    # scheme and tunnel was tested in one connection
                    $cb->($proxy_type);
                }
            }

            return;
        }
    );

    return;
}

sub _test_scheme ( $self, $scheme, $proxy_type, $cb ) {
    if ( defined $self->{test_scheme}->{$scheme}->{$proxy_type} ) {    # scheme was tested
        $cb->( $self->{test_scheme}->{$scheme}->{$proxy_type} );       # return cached result
    }
    else {                                                             # scheme wasn't tested
        unless ( $CHECK_SCHEME->{$scheme}->[2] ) {                     # can't test scheme
            $self->{test_scheme}->{$scheme}->{$proxy_type} = 1;        # cache and return positive result

            $cb->(1);
        }
        else {                                                         # start test scheme
            $self->_test_connection(
                $CHECK_SCHEME->{$scheme}->[1],
                $proxy_type,
                sub ($h) {
                    if ($h) {                                          # proxy connected + tunnel created
                        $CHECK_SCHEME->{$scheme}->[2]->(               # run scheme test
                            $self, $scheme, $h,
                            $proxy_type,
                            sub ($scheme_ok) {
                                $self->{test_scheme}->{$scheme}->{$proxy_type} = $scheme_ok;

                                $cb->($scheme_ok);

                                return;
                            }
                        );
                    }
                    else {                                             # proxy disabled, proxy connect error or tunnel create error
                        $self->{test_scheme}->{$scheme}->{$proxy_type} = 0;

                        $cb->(0);
                    }

                    return;
                }
            );
        }
    }

    return;
}

sub _test_connection ( $self, $connect, $proxy_type, $cb ) {
    Pcore::AE::Handle->new(
        connect          => [ $self->host->name, $self->port ],
        connect_timeout  => 10,
        timeout          => 10,
        persistent       => 0,
        on_connect_error => sub ( $h, $message ) {
            $self->disable;

            $cb->(undef);

            return;
        },
        on_connect => sub ( $h, @ ) {
            if ( $proxy_type == $PROXY_TYPE_HTTP ) {
                $cb->($h);
            }
            else {
                my $on_error = sub ( $h, $message, $disable_proxy = 0 ) {
                    $self->disable if $disable_proxy;

                    $cb->(undef);

                    return;
                };

                my $on_connect = sub ($hdl) {
                    $cb->($h);

                    return;
                };

                $h->on_error(
                    sub($h, $fatal, $message) {
                        $on_error->( $h, $message, 0 );

                        return;
                    }
                );

                if ( $proxy_type == $PROXY_TYPE_CONNECT ) {
                    $h->_connect_proxy_connect( $self, $connect, $on_error, $on_connect );
                }
                elsif ( $proxy_type == $PROXY_TYPE_SOCKS4 || $proxy_type == $PROXY_TYPE_SOCKS4A ) {
                    $h->_connect_proxy_socks4( $self, $connect, $on_error, $on_connect );
                }
                elsif ( $proxy_type == $PROXY_TYPE_SOCKS5 ) {
                    $h->_connect_proxy_socks5( $self, $connect, $on_error, $on_connect );
                }
                else {
                    die 'Invalid proxy type, please report';
                }
            }

            return;
        },
    );

    return;
}

sub _test_scheme_httpx ( $self, $scheme, $h, $proxy_type, $cb ) {
    state $req_http_http = q[GET http://www.google.com/favicon.ico HTTP/1.0] . $CRLF . $CRLF;

    state $req_http_https = q[GET https://www.google.com/favicon.ico HTTP/1.0] . $CRLF . $CRLF;

    state $req_tunnel = qq[GET /favicon.ico HTTP/1.1${CRLF}Host: www.google.com${CRLF}${CRLF}];

    if ( $proxy_type == $PROXY_TYPE_HTTP ) {
        $h->push_write( $scheme eq 'http' ? $req_http_http : $req_http_https );
    }
    else {
        $h->starttls('connect') if $scheme eq 'https';

        $h->push_write($req_tunnel);
    }

    $h->read_http_res_headers(
        headers => 0,
        sub ( $hdl, $res, $error_reason ) {
            if ( $error_reason || $res->{status} != 200 ) {    # headers parsing error
                $cb->(0);
            }
            else {
                $h->push_read(
                    chunk => 10,
                    sub ( $hdl, $chunk ) {

                        # remove chunk size in case of chunked transfer encoding
                        $chunk =~ s/\A[[:xdigit:]]+\r\n//sm;

                        # cut to 4 chars
                        substr $chunk, 4, 10, q[];

                        # validate .ico header
                        if ( $chunk eq qq[\x00\x00\x01\x00] ) {
                            $cb->(1);
                        }
                        else {
                            $cb->(0);
                        }

                        return;
                    }
                );
            }

            return;
        }
    );

    return;
}

# TODO
sub _test_scheme_whois ( $self, $scheme, $h, $proxy_type, $cb ) {
    $cb->(0);

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 91                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 395, 449             │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 449                  │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_test_scheme_whois' declared but    │
## │      │                      │ not used                                                                                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 83, 87, 106, 120     │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 429                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 478                  │ Documentation::RequirePackageMatchesPodName - Pod NAME on line 482 does not match the package declaration      │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Proxy - Proxy lists management subsystem

=head1 SYNOPSIS

    use Pcore::Proxy::Pool;

    my $pool = Pcore::Proxy::Pool->new(
        {   source => [
                {   class => 'Tor',
                    host  => '192.168.175.1',
                    port  => 9050,
                },
                {   class   => 'List',
                    proxies => [         #
                        'connect://107.153.45.156:80',
                        'connect://23.247.255.3:80',
                        'connect://23.247.255.2:80',
                        'connect://104.144.28.45:80',
                        'connect://107.173.180.52:80',
                        'connect://155.94.218.158:80',
                        'connect://155.94.218.160:80',
                        'connect://198.23.216.57:80',
                        'connect://172.245.109.210:80',
                        'connect://107.173.180.156:80',
                    ],
                },
            ],
        }
    );

    $pool->get_proxy(
        ['connect', 'socks'],
        sub ($proxy = undef) {
            ...;

            return;
        }
    );

=head1 DESCRIPTION

=cut
