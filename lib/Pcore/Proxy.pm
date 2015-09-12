package Pcore::Proxy v0.1.0;

use Pcore qw[-export -class];
use Scalar::Util qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use Const::Fast qw[const];

our @EXPORT_OK   = qw[$PROXY_HTTP $PROXY_CONNECT $PROXY_SOCKS5 $PROXY_SOCKS4 $PROXY_SOCKS4A];
our %EXPORT_TAGS = (                                                                            #
    CONST => \@EXPORT_OK
);
our @EXPORT = ();

extends qw[Pcore::Util::URI];

has id      => ( is => 'lazy', isa => Str, init_arg => undef );
has refaddr => ( is => 'lazy', isa => Int, init_arg => undef );

has is_checked => ( is => 'ro', default => 0, init_arg => undef );
has is_enabled => ( is => 'ro', default => 0, init_arg => undef );                              # proxy has working protocols, this is the result of the check operation and could not be changed manually

has is_http    => ( is => 'ro', default => 0, init_arg => undef );
has is_connect => ( is => 'ro', default => 0, init_arg => undef );                              # means, that proxy support CONNECT method to ANY port
has is_https   => ( is => 'ro', default => 0, init_arg => undef );                              # means, that proxy support CONNECT method ONLY to port 443
has is_socks   => ( is => 'ro', default => 0, init_arg => undef );
has is_socks5  => ( is => 'ro', default => 0, init_arg => undef );
has is_socks4  => ( is => 'ro', default => 0, init_arg => undef );
has is_socks4a => ( is => 'ro', default => 0, init_arg => undef );

around new => sub ( $orig, $self, $uri ) {
    if ( my $args = $self->_parse_uri($uri) ) {
        $self->$orig($args);
    }
    else {
        return;
    }
};

no Pcore;

# TODO - change indexes
const our $PROXY_HTTP    => 6;
const our $PROXY_CONNECT => 1;
const our $PROXY_SOCKS5  => 3;
const our $PROXY_SOCKS4  => 4;
const our $PROXY_SOCKS4A => 5;

const our $TYPE_CONNECT => 1;
const our $TYPE_HTTPS   => 2;
const our $TYPE_SOCKS5  => 3;
const our $TYPE_SOCKS4  => 4;
const our $TYPE_SOCKS4A => 5;
const our $TYPE_HTTP    => 6;

const our $TYPE_SCHEME => {
    connect => $TYPE_CONNECT,
    https   => $TYPE_HTTPS,
    socks5  => $TYPE_SOCKS5,
    socks4  => $TYPE_SOCKS4,
    socks4a => $TYPE_SOCKS4A,
    http    => $TYPE_HTTP,
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

sub check ( $self, $cb = undef, $connect_timeout = 5, $timeout = 10 ) {
    state $cb_cache = {};

    my $id = $self->id;

    $cb_cache->{$id} //= [];

    if ( $cb_cache->{$id}->@* ) {
        push $cb_cache->{$id}->@*, [ $self, $cb ];

        return;
    }

    push $cb_cache->{$id}->@*, [ $self, $cb ];

    my $res = {};

    my $handle;

    state $req = qq[GET /favicon.ico HTTP/1.1${CRLF}Host: www.google.com${CRLF}${CRLF}];

    my $cv = AE::cv sub {
        $handle->destroy if $handle;

        my $processed_objects = {};

        # run callbacks
        for ( $cb_cache->{$id}->@* ) {
            my $refaddr = $_->[0]->refaddr;

            if ( !exists $processed_objects->{$refaddr} ) {
                $processed_objects->{$refaddr} = 1;

                my $is_enabled = 0;

                my $is_socks = 0;

                # socks5
                if ( $res->{socks5} ) {
                    $is_enabled = 1;

                    $is_socks = 1;

                    $_->[0]->{is_socks5} = $TYPE_SOCKS5;
                }
                else {
                    $_->[0]->{is_socks5} = 0;
                }

                # socks4
                if ( $res->{socks4} ) {
                    $is_enabled = 1;

                    $is_socks = 1;

                    $_->[0]->{is_socks4} = $TYPE_SOCKS4;
                }
                else {
                    $_->[0]->{is_socks4} = 0;
                }

                # socks4a
                if ( $res->{socks4a} ) {
                    $is_enabled = 1;

                    $is_socks = 1;

                    $_->[0]->{is_socks4a} = $TYPE_SOCKS4A;
                }
                else {
                    $_->[0]->{is_socks4a} = 0;
                }

                # socks
                $_->[0]->{is_socks} = $is_socks;

                # connect && https
                if ( $res->{connect} ) {
                    $is_enabled = 1;

                    $_->[0]->{is_connect} = $TYPE_CONNECT;

                    $_->[0]->{is_https} = $TYPE_HTTPS;
                }
                else {
                    $_->[0]->{is_connect} = 0;
                }

                # https
                if ( $res->{https} ) {
                    $is_enabled = 1;

                    $_->[0]->{is_https} = $TYPE_HTTPS;
                }
                else {
                    $_->[0]->{is_https} = 0;
                }

                # http
                if ( $res->{http} ) {
                    $is_enabled = 1;

                    $_->[0]->{is_http} = $TYPE_HTTP;
                }
                else {
                    $_->[0]->{is_http} = 0;
                }

                $_->[0]->{is_checked} = 1;

                $_->[0]->{is_enabled} = $is_enabled;
            }

            $_->[1]->( $_->[0] ) if $_->[1];
        }

        delete $cb_cache->{$id};

        return;
    };

    my $test_req = sub ( $h, $req, $tls, $cb ) {
        $h->timeout($timeout);

        $h->on_error(
            sub ( $h, $fatal, $message ) {
                $h->destroy;

                $cb->(0);

                return;
            }
        );

        $h->starttls('connect') if $tls;

        $h->push_write($req);

        $h->read_http_res_headers(
            headers => 0,
            sub ( $h, $res, $error_reason ) {
                if ($error_reason) {    # headers parsing error
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
    };

    my $http = sub {
        $cv->begin;

        $handle->destroy if $handle;

        $handle = Pcore::AE::Handle->new(
            connect          => [ $self->host->name, $self->port ],
            proxy            => $self,
            proxy_type       => $TYPE_HTTP,
            connect_timeout  => $connect_timeout,
            on_connect_error => sub ( $h, $message ) {
                $cv->end;

                return;
            },
            on_connect => sub ( $h, @ ) {
                my $http_req = q[GET http://www.google.com/favicon.ico HTTP/1.0] . $CRLF;

                $http_req .= q[Proxy-Authorization: Basic ] . $self->userinfo_b64 if $self->userinfo;

                $http_req .= $CRLF;

                $test_req->(
                    $h,
                    $http_req,
                    0,
                    sub($is_valid) {
                        $res->{http} = $is_valid;

                        $cv->end;

                        return;
                    },
                );

                return;
            },
        );

        return;
    };

    my $https = sub {
        $cv->begin;

        $handle->destroy if $handle;

        $handle = Pcore::AE::Handle->new(
            connect                => [ 'google.com', 443 ],
            proxy                  => $self,
            proxy_type             => $TYPE_HTTPS,
            connect_timeout        => $connect_timeout,
            on_proxy_connect_error => sub ( $h, $message, $is_connect_error ) {
                $http->() if !$is_connect_error;    # goto https proxy check if handshake error was occured

                $cv->end;

                return;
            },
            on_connect_error => sub ( $h, $message ) {
                $http->();

                $cv->end;

                return;
            },
            on_connect => sub ( $h, @ ) {
                $test_req->(
                    $h, $req, 1,
                    sub($is_valid) {
                        $res->{https} = $is_valid;

                        $http->();

                        $cv->end;

                        return;
                    }
                );

                return;
            },
        );

        return;
    };

    my $connect = sub {
        $cv->begin;

        $handle->destroy if $handle;

        $handle = Pcore::AE::Handle->new(
            connect                => [ 'google.com', 80 ],
            proxy                  => $self,
            proxy_type             => $TYPE_CONNECT,
            connect_timeout        => $connect_timeout,
            on_proxy_connect_error => sub ( $h, $message, $is_connect_error ) {
                $https->() if !$is_connect_error;    # goto https proxy check if handshake error was occured

                $cv->end;

                return;
            },
            on_connect_error => sub ( $h, $message ) {
                $https->();

                $cv->end;

                return;
            },
            on_connect => sub ( $h, @ ) {
                $test_req->(
                    $h, $req, 0,
                    sub($is_valid) {
                        $res->{connect} = $is_valid;

                        $res->{https} = $is_valid;

                        $http->();

                        $cv->end;

                        return;
                    }
                );

                return;
            },
        );

        return;
    };

    my $socks5 = sub {
        $cv->begin;

        $handle->destroy if $handle;

        $handle = Pcore::AE::Handle->new(
            connect                => [ 'google.com', 80 ],
            proxy                  => $self,
            proxy_type             => $TYPE_SOCKS5,
            connect_timeout        => $connect_timeout,
            on_proxy_connect_error => sub ( $h, $message, $is_connect_error ) {
                $connect->() if !$is_connect_error;    # goto connect proxy check if handshake error was occured

                $cv->end;

                return;
            },
            on_connect_error => sub ( $h, $message ) {
                $connect->();

                $cv->end;

                return;
            },
            on_connect => sub ( $h, @ ) {
                $test_req->(
                    $h, $req, 0,
                    sub($is_valid) {
                        $res->{socks5} = $is_valid;

                        $connect->();

                        $cv->end;

                        return;
                    }
                );

                return;
            },
        );

        return;
    };

    # run checkers
    $socks5->();

    return;
}

sub _build_id ($self) {
    return $self->hostport;
}

sub _build_refaddr ($self) {
    return Scalar::Util::refaddr($self);
}

sub disable ( $self, $timeout = undef ) {
    return;
}

sub ban ( $self, $key, $timeout = undef ) {
    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 94                   │ Subroutines::ProhibitExcessComplexity - Subroutine "check" with high complexity score (31)                     │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 250                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
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
