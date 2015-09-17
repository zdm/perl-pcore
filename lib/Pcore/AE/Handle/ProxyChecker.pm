package Pcore::AE::Handle::ProxyChecker;

use Pcore qw[-class];
use Pcore::AE::Handle;
use Pcore::AE::Handle::Const qw[:PROXY_TYPE :PROXY_ERROR];
use Pcore::Proxy;
use Const::Fast qw[const];

has cb => ( is => 'ro', isa => CodeRef, required => 1 );
has proxy => ( is => 'ro', isa => InstanceOf ['Pcore::Proxy'], required => 1 );
has connect_host   => ( is => 'ro', isa => Str,         required => 1 );
has connect_port   => ( is => 'ro', isa => PositiveInt, required => 1 );
has connect_scheme => ( is => 'ro', isa => Str,         default  => q[tcp] );
has timeout        => ( is => 'ro', isa => Int,         default  => 5 );

has connect    => ( is => 'lazy', isa => ArrayRef, init_arg => undef );
has connect_id => ( is => 'lazy', isa => Str,      init_arg => undef );
has connect_test => ( is => 'lazy', isa => Maybe [ArrayRef], init_arg => undef );
has connect_test_host => ( is => 'lazy', isa => Str, init_arg => undef );
has connect_test_port => ( is => 'lazy', isa => Int, init_arg => undef );
has connect_test_code => ( is => 'lazy', isa => Maybe [CodeRef], init_arg => undef );

no Pcore;

const our $CONNECT_SCHEME => {
    tcp => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS ] ],    # default scheme
    udp => [ [$PROXY_TYPE_SOCKS] ],
    http  => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS, $PROXY_TYPE_HTTP ], [ 'www.google.com', 80 ],  \&_test_scheme_http, ],
    https => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS, $PROXY_TYPE_HTTP ], [ 'www.google.com', 443 ], \&_test_scheme_http, ],
    whois => [ [ $PROXY_TYPE_CONNECT, $PROXY_TYPE_SOCKS ], [ 'whois.iana.org', 43 ], \&_test_whois, ],
};

# TODO
# process timeout errors - install on_error;
# differ for connect, handshare and other errors;
# whois scheme;
# stack calls with the same args;

# CONSTRUCTOR
sub check ( $self, $proxy, $connect, @ ) {
    my %args = (
        cb => pop,
        @_[ 3 .. $#_ ],
    );

    $args{proxy} = ref $proxy ? $proxy : Pcore::Proxy->new($proxy);

    $connect = P->uri($connect) if !ref $connect;

    if ( ref $connect eq 'ARRAY' ) {
        ( $args{connect_host}, $args{connect_port}, $args{connect_scheme} ) = $connect->@*;
    }
    else {
        ( $args{connect_host}, $args{connect_port}, $args{connect_scheme} ) = ( $connect->host->name, $connect->connect_port, $connect->scheme );
    }

    $args{connect_scheme} ||= 'tcp';

    return $self->new( \%args )->_run;
}

# BUILDRS
sub _build_connect ($self) {
    return $CONNECT_SCHEME->{ $self->connect_scheme };
}

sub _build_connect_id ($self) {
    return $self->connect_scheme . q[:] . $self->connect_port;
}

sub _build_connect_test ($self) {
    return $self->connect->[1];
}

sub _build_connect_test_host ($self) {
    return $self->connect->[1] ? $self->connect->[1]->[0] : q[];
}

sub _build_connect_test_port ($self) {
    return $self->connect->[1] ? $self->connect->[1]->[1] : 0;
}

sub _build_connect_test_code ($self) {
    return $self->connect->[2];
}

sub _run ($self) {
    $self->proxy->start_thread;

    my @tests = $self->connect->[0]->@*;

    my $test = sub ($proxy_type) {

        # return immediately, if we can't connect to the proxy
        if ( !$self->proxy->is_enabled ) {
            $self->_finish(0);

            return;
        }

        if ($proxy_type) {    # found working proxy type
            $self->_finish($proxy_type);
        }
        else {
            if ( $proxy_type = shift @tests ) {
                if ( $proxy_type == $PROXY_TYPE_HTTP ) {
                    $self->_test_http( __SUB__, $proxy_type );
                }
                elsif ( $proxy_type == $PROXY_TYPE_CONNECT ) {
                    $self->_test_connect( __SUB__, $proxy_type );
                }
                else {
                    $self->_test_socks( __SUB__, $proxy_type );
                }
            }
            else {
                $self->_finish(0);
            }
        }

        return;
    };

    $test->(0);

    return;
}

sub _finish ( $self, $proxy_type ) {
    undef $self->{h};

    $self->proxy->finish_thread;

    $self->cb->( $self->proxy, 0 );

    return;
}

# PROXY TYPE TEST METHODS
sub _test_http ( $self, $cb, $test_type ) {
    $cb->(0);

    return;
}

sub _test_connect ( $self, $cb, $proxy_type ) {
    my $proxy = $self->proxy;

    # return if proxy is disabled
    return $cb->($PROXY_ERROR_CONNECT) if !$proxy->is_enabled;

    # return if proxy is not CONNECT proxy
    return $cb->($PROXY_ERROR_OTHER) if defined $proxy->is_connect && !$proxy->is_connect;

    my $connect;

    my $test;

    if ( $self->connect_test_code ) {
        if ( $self->connect_test_port == $self->connect_port ) {
            $connect = $self->connect_test;

            # test port and connect port are the same
            # we can test port and scheme in one connection
            $test = $self->connect_test_code;
        }
        else {
            $connect = [ $self->connect_host, $self->connect_port ];

            $test = sub ( $self, $proxy_type, $cb ) {
                $self->{h} = Pcore::AE::Handle->new(
                    connect         => $self->connect_test,
                    connect_timeout => $self->timeout,
                    timeout         => $self->timeout,
                    proxy           => $self->proxy,
                    proxy_type      => $proxy_type,
                    on_connect      => sub ( $h, @ ) {
                        $self->connect_test_code->( $self, $proxy_type, $cb );

                        return;
                    }
                );

                return;
            };
        }
    }
    else {
        $connect = [ $self->connect_host, $self->connect_port ];

        # we have no test code for scheme
        # so, we just can test TCP tunnel creation to the distination port
        $test = sub ( $self, $proxy_type, $cb ) {
            $cb->($proxy_type);

            return;
        };
    }

    $self->{h} = Pcore::AE::Handle->new(
        connect                => $connect,
        connect_timeout        => $self->timeout,
        timeout                => $self->timeout,
        proxy                  => $self->proxy,
        proxy_type             => $proxy_type,
        on_proxy_connect_error => sub ( $h, $message, $connect_error ) {
            if ($connect_error) {

                # TODO disable proxy
            }

            $cb->(0);

            return;
        },
        on_connect_error => sub ( $h, $message ) {

            # can't establish TCP tunnel
            $cb->(0);

            return;
        },
        on_connect => sub ( $h, @ ) {
            $test->( $self, $proxy_type, $cb );

            return;
        },
    );

    return;
}

sub _test_socks ( $self, $cb, $test_type ) {
    $cb->(0);

    return;
}

# SCHEME TEST METHODS
sub _test_scheme_http ( $self, $proxy_type, $cb ) {
    state $req_http_http = q[GET http://www.google.com/favicon.ico HTTP/1.0] . $CRLF . $CRLF;

    state $req_http_https = q[GET https://www.google.com/favicon.ico HTTP/1.0] . $CRLF . $CRLF;

    state $req_tunnel = qq[GET /favicon.ico HTTP/1.1${CRLF}Host: www.google.com${CRLF}${CRLF}];

    if ( $proxy_type == $PROXY_TYPE_HTTP ) {
        $self->{h}->push_write( $self->connect_scheme eq 'http' ? $req_http_http : $req_http_https );
    }
    else {
        $self->{h}->starttls('connect') if $self->connect_scheme eq 'https';

        $self->{h}->push_write($req_tunnel);
    }

    $self->{h}->read_http_res_headers(
        headers => 0,
        sub ( $h, $res, $error_reason ) {
            if ( $error_reason || $res->{status} != 200 ) {

                # headers parsing error
                $cb->(0);
            }
            else {
                $h->push_read(
                    chunk => 10,
                    sub ( $h, $chunk ) {

                        # remove chunk size in case of chunked transfer encoding
                        $chunk =~ s/\A[[:xdigit:]]+\r\n//sm;

                        # cut to 4 chars
                        substr $chunk, 4, 10, q[];

                        # validate .ico header
                        if ( $chunk eq qq[\x00\x00\x01\x00] ) {
                            $cb->($proxy_type);
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 276                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 453                  │ Documentation::RequirePackageMatchesPodName - Pod NAME on line 457 does not match the package declaration      │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__


# TODO
sub _check_http_proxy ($self) {
    my $test;

    if ( $self->test_scheme eq 'http' ) {
        $test = $TEST_SCHEME->{http}->[1];
    }
    elsif ( $self->test_scheme eq 'https' ) {
        $test = $TEST_SCHEME->{https}->[1];
    }
    else {

        # http proxy can work only with http or https schemes
        return $self->_finish($ERROR_PROTOCOL);
    }

    # test connect to the proxy
    $self->{h} = Pcore::AE::Handle->new(
        connect         => [ $self->proxy->host->name, $self->proxy->port ],
        connect_timeout => $self->timeout,
        timeout         => $self->timeout,

        # TODO disable proxy
        on_connect_error => sub ( $h, $message ) {
            $self->_finish($ERROR_CONNECT);

            return;
        },
        on_error => sub ( $h, $fatal, $message ) {
            $self->_finish($ERROR_PROTOCOL);

            return;
        },
        on_connect => sub ( $h, @ ) {
            $test->($self);

            return;
        }
    );

    return;
}

# TODO
sub _check_tunnel_proxy ($self) {
    my $connect;

    my $test_scheme = $TEST_SCHEME->{ $self->test_scheme };

    my $test;

    if ($test_scheme) {
        if ( $test_scheme->[0]->[1] == $self->test_port ) {
            $connect = $test_scheme->[0];

            $test = $test_scheme->[1];
        }
        else {
            $connect = [ $self->test_host, $self->test_port ];

            $test = sub ($self) {
                $self->{h} = Pcore::AE::Handle->new(
                    connect         => $test_scheme->[0],
                    connect_timeout => $self->timeout,
                    timeout         => $self->timeout,
                    proxy           => $self->proxy,
                    proxy_type      => $self->proxy_type,
                    on_connect      => sub ( $h, @ ) {
                        $test_scheme->[1]->($self);

                        return;
                    }
                );

                return;
            };
        }
    }
    else {
        $connect = [ $self->test_host, $self->test_port ];

        $test = sub ($self) {
            $self->_finish($ERROR_NO);

            return;
        };
    }

    $self->{h} = Pcore::AE::Handle->new(
        connect                => $connect,
        connect_timeout        => $self->timeout,
        timeout                => $self->timeout,
        proxy                  => $self->proxy,
        proxy_type             => $self->proxy_type,
        on_proxy_connect_error => sub ( $h, $message, $connect_error ) {
            $self->_finish($ERROR_CONNECT);

            return;
        },
        on_connect_error => sub ( $h, $message ) {
            $self->_finish($ERROR_CONNECT);

            return;
        },
        on_connect => sub ( $h, @ ) {
            $test->($self);

            return;
        },
    );

    return;
}

# TODO
sub _finish ( $self, $status ) {
    $self->{h}->destroy if $self->{h};

    if ( $status != $ERROR_NO ) {
        if ( $status == $ERROR_PROTOCOL ) {

            # TODO disable proxy
        }

        $self->cb->(0);
    }
    else {
        $self->cb->(1);
    }

    return;
}

# TODO
sub _test_whois ($self) {
    $self->_finish($ERROR_NO);

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Handle::Proxy

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
