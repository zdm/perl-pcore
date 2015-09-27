package Pcore::AE::Handle::ProxyPool::Proxy;

use Pcore qw[-class];
use Pcore::AE::Handle::ProxyPool::Proxy::Removed;
use Pcore::AE::Handle qw[:ALL];
use Const::Fast qw[const];

extends qw[Pcore::Util::URI];

has source => ( is => 'ro', isa => ConsumerOf ['Pcore::AE::Handle::ProxyPool::Source'], required => 1, weak_ref => 1 );

has id      => ( is => 'lazy', isa => Str, init_arg => undef );
has pool_id => ( is => 'ro',   isa => Int, init_arg => undef );

has connect_error_timeout => ( is => 'lazy', isa => PositiveInt );
has max_connect_errors    => ( is => 'lazy', isa => PositiveInt );
has ban_timeout           => ( is => 'lazy', isa => PositiveOrZeroInt );
has max_threads           => ( is => 'lazy', isa => PositiveOrZeroInt );

has removed       => ( is => 'ro', default => 0, init_arg => undef );
has connect_error => ( is => 'ro', default => 0, init_arg => undef );

has test_connection => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );
has test_scheme     => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

has connect_error_time => ( is => 'ro', isa => Int, default => 0, init_arg => undef );
has connect_errors     => ( is => 'ro', isa => Int, default => 0, init_arg => undef );
has threads            => ( is => 'ro', isa => Int, default => 0, init_arg => undef );
has total_threads      => ( is => 'ro', isa => Int, default => 0, init_arg => undef );

has is_proxy_pool => ( is => 'ro', default => 0, init_arg => undef );

around new => sub ( $orig, $self, $uri, $source ) {
    $uri = q[//] . $uri if index( $uri, q[//] ) == -1;

    my $args = $self->parse_uri_string($uri);

    return if !$args->{authority};

    my $userinfo = q[];

    if ( ( my $idx = index $args->{authority}, q[@] ) != -1 ) {
        $userinfo = substr $args->{authority}, 0, $idx + 1, q[];
    }

    # parse userinfo
    my @token = split /:/sm, $args->{authority};

    if ( @token < 2 ) {
        die 'Proxy port should be specified';
    }
    elsif ( @token == 2 ) {
        $args->{authority} = $userinfo . $args->{authority};
    }
    elsif ( @token == 3 ) {    # host:port:username
        $args->{authority} = $token[2] . q[@] . $token[0] . q[:] . $token[1];
    }
    else {                     # host:port:username:password
        $args->{authority} = shift(@token) . q[:] . shift(@token);

        $args->{authority} = join( q[:], @token ) . q[@] . $args->{authority};
    }

    $args->{source} = $source;

    return $self->$orig($args);
};

no Pcore;

const our $CHECK_SCHEME => {
    tcp => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS4, $PROXY_TYPE_SOCKS5 ] ],    # default scheme
    udp => [ [$PROXY_TYPE_SOCKS5] ],
    http  => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS4, $PROXY_TYPE_SOCKS5, $PROXY_TYPE_HTTP ], [ 'www.google.com', 80 ],  \&_test_scheme_httpx, ],
    https => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS4, $PROXY_TYPE_SOCKS5, $PROXY_TYPE_HTTP ], [ 'www.google.com', 443 ], \&_test_scheme_httpx, ],
    whois => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS4, $PROXY_TYPE_SOCKS5 ], [ 'whois.iana.org', 43 ], \&_test_whois, ],
};

sub _build_id ($self) {
    return $self->hostport;
}

sub _build_connect_error_timeout ($self) {
    return $self->source->connect_error_timeout;
}

sub _build_max_connect_errors ($self) {
    return $self->source->max_connect_errors;
}

sub _build_ban_timeout ($self) {
    return $self->source->pool->ban_timeout;
}

sub _build_max_threads ($self) {
    return $self->source->max_threads_proxy;
}

# TODO remove from ban lists
sub remove ($self) {
    state $q1 = $self->source->pool->dbh->query('DELETE FROM `proxy` WHERE `pool_id` = ?');

    $q1->do( bind => [ $self->pool_id ] );

    delete $self->source->pool->list->{ $self->id };

    # TODO remove from ban lists

    $self->%* = (
        removed       => 1,
        connect_error => 1,
    );

    bless $self, 'Pcore::AE::Handle::ProxyPool::Proxy::Removed';

    return;
}

# TODO
sub ban ( $self, $host, $timeout = undef ) {
    return if $self->source->is_multiproxy;

    $timeout //= $self->ban_timeout;

    return;
}

# CONNECT METHODS
# TODO should be called AUTOMATICALLY after each connect attempt
sub connect_ok ($self) {
    $self->{connect_errors} = 0;

    # drop "connect_error" flag
    if ( $self->{connect_error} ) {
        $self->{connect_error} = 0;

        state $q1 = $self->source->pool->dbh->query('UPDATE `proxy` SET `connect_error` = 0 WHERE `pool_id` = ?');

        $q1->do( bind => [ $self->pool_id ] );
    }

    return;
}

sub connect_failure ($self) {
    return if $self->{connect_error};

    # set "connect_error" flag
    $self->{connect_error} = 0;

    $self->{connect_errors}++;

    if ( $self->{connect_errors} >= $self->max_connect_errors ) {
        $self->remove;
    }
    else {
        state $q1 = $self->source->pool->dbh->query('UPDATE `proxy` SET `connect_error` = 1, `connect_error_time` = ? WHERE `pool_id` = ?');

        $self->{connect_error_time} = time + $self->connect_error_timeout;

        $q1->do( bind => [ $self->{connect_error_time}, $self->pool_id ] );
    }

    return;
}

sub _start_thread ($self) {
    $self->{threads}++;

    $self->{total_threads}++;

    state $q1 = $self->source->pool->dbh->query('UPDATE `proxy` SET `threads` = ?, `total_threads` = ? WHERE `pool_id` = ?');

    $q1->do( bind => [ $self->{threads}, $self->{total_threads}, $self->{pool_id} ] );

    $self->{source}->start_thread;

    return;
}

# TODO call waiting callbacks
# if proxy has connect_error - call all callbacks
sub finish_thread ($self) {
    $self->{threads}--;

    state $q1 = $self->source->pool->dbh->query('UPDATE `proxy` SET `threads` = ? WHERE `pool_id` = ?');

    $q1->do( bind => [ $self->{threads}, $self->{pool_id} ] );

    $self->{source}->finish_thread;

    return;
}

# CONNECT
sub can_connect ( $self, $connect, $cb ) {
    my $can_connect = !$self->{connect_error} && $self->{source}->can_connect && $self->{threads} < $self->max_threads;

    if ( !$can_connect ) {

        # TODO cache cb
        $cb->(0);
    }
    else {
        state $callback = {};

        $connect->[2] //= 'tcp';

        $connect->[3] = $connect->[2] . q[_] . $connect->[1];

        $self->source->pool->_add_connect_id( $connect->[3] );

        $self->_start_thread;

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
                if ( !$self->{connect_error} && !$proxy_type && ( $proxy_type = shift @types ) ) {
                    if ( $proxy_type == $PROXY_TYPE_HTTP ) {
                        $self->_check_http( $proxy_type, $connect, __SUB__ );
                    }
                    else {
                        $self->_check_tunnel( $proxy_type, $connect, __SUB__ );
                    }
                }
                else {
                    $self->{test_connection}->{ $connect->[3] } = $proxy_type;    # cache connection test result

                    $self->source->pool->dbh->do( qq[UPDATE `proxy` SET `$connect->[3]` = $proxy_type WHERE pool_id = ?], bind => [ $self->pool_id ] );

                    while ( my $cb = shift $callback->{$cache_key}->@* ) {
                        $cb->($proxy_type);
                    }

                    delete $callback->{$cache_key};
                }
            };

            $test->(0);
        }
    }

    return;
}

sub get_slot ( $self, $connect, $cb ) {
    $cb->( $self, $PROXY_TYPE_HTTP );

    return;
}

# CHECK PROXY
sub _check_http ( $self, $proxy_type, $connect, $cb ) {
    $self->_test_scheme(
        $connect->[2],
        $proxy_type,
        sub ($scheme_ok) {
            if ($scheme_ok) {    # scheme test failed
                $cb->($proxy_type);
            }
            else {               # scheme test passed
                $cb->(0);
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
            if ( !$scheme_ok ) {    # scheme test failed
                $cb->(0);
            }
            else {                  # scheme test passed

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
                    # scheme and tunnel was tested in single connection
                    $cb->($proxy_type);
                }
            }

            return;
        }
    );

    return;
}

sub _test_connection ( $self, $connect, $proxy_type, $cb ) {
    Pcore::AE::Handle->new(
        connect          => [ $self->host->name, $self->port ],
        connect_timeout  => 10,
        timeout          => 10,
        persistent       => 0,
        on_connect_error => sub ( $h, $message ) {
            $self->connect_failure;

            $cb->(undef);

            return;
        },
        on_connect => sub ( $h, @ ) {
            if ( $proxy_type == $PROXY_TYPE_HTTP ) {
                $self->connect_ok;

                $cb->($h);
            }
            else {
                Pcore::AE::Handle::ConnectProxy::connect_proxy(
                    $h, $self,
                    $proxy_type,
                    $connect,
                    timeout => 10,
                    sub ( $h, $status, $message ) {
                        if ( $status == $PROXY_OK ) {
                            $self->connect_ok;

                            $cb->($h);
                        }
                        else {
                            # $self->connect_failure : $self->connect_ok

                            $cb->(undef);
                        }

                        return;
                    }
                );
            }

            return;
        },
    );

    return;
}

sub _test_scheme ( $self, $scheme, $proxy_type, $cb ) {
    if ( !$CHECK_SCHEME->{$scheme}->[2] ) {    # scheme wasn't tested and can't be tested
        $cb->(1);
    }
    elsif ( defined $self->{test_scheme}->{$scheme}->{$proxy_type} ) {    # scheme was tested
        $cb->( $self->{test_scheme}->{$scheme}->{$proxy_type} );          # return cached result
    }
    else {                                                                # scheme wasn't tested and can be tested
        $self->_test_connection(
            $CHECK_SCHEME->{$scheme}->[1],
            $proxy_type,
            sub ($h) {
                if ($h) {                                                 # proxy connected + tunnel created
                    $CHECK_SCHEME->{$scheme}->[2]->(                      # run scheme test
                        $self, $scheme, $h,
                        $proxy_type,
                        sub ($scheme_ok) {
                            $self->{test_scheme}->{$scheme}->{$proxy_type} = $scheme_ok;

                            $cb->($scheme_ok);

                            return;
                        }
                    );
                }
                else {                                                    # proxy disabled, proxy connect error or tunnel create error
                    $self->{test_scheme}->{$scheme}->{$proxy_type} = 0;

                    $cb->(0);
                }

                return;
            }
        );
    }

    return;
}

sub _test_scheme_httpx ( $self, $scheme, $h, $proxy_type, $cb ) {
    if ( $proxy_type == $PROXY_TYPE_HTTP ) {
        my $auth_header = $self->userinfo ? q[Proxy-Authorization: Basic ] . $self->userinfo_b64 . $CRLF : q[];

        if ( $scheme eq 'http' ) {
            $h->push_write(qq[GET http://www.google.com/favicon.ico HTTP/1.0${CRLF}${auth_header}${CRLF}]);
        }
        else {
            $h->push_write(qq[GET https://www.google.com/favicon.ico HTTP/1.0${CRLF}${auth_header}${CRLF}]);
        }
    }
    else {
        $h->starttls('connect') if $scheme eq 'https';

        $h->push_write(qq[GET /favicon.ico HTTP/1.1${CRLF}Host: www.google.com${CRLF}${CRLF}]);
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
## │    3 │ 109                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 211                  │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 418, 473             │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 473                  │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_test_scheme_whois' declared but    │
## │      │                      │ not used                                                                                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 101, 105, 137, 157,  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## │      │ 172, 186, 245        │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 453                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 59                   │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 507                  │ Documentation::RequirePackageMatchesPodName - Pod NAME on line 511 does not match the package declaration      │
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
