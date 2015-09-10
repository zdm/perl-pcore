package Pcore::AE::Handle::Proxy;

use Pcore qw[-class];
use Pcore::AE::Handle;
use Pcore::Proxy qw[:CONST];
use Const::Fast qw[const];

has cb => ( is => 'ro', isa => CodeRef, required => 1 );
has proxy => ( is => 'ro', isa => InstanceOf ['Pcore::Proxy'], required => 1 );
has proxy_type  => ( is => 'ro', isa => Int,         required => 1 );
has test_host   => ( is => 'ro', isa => Str,         required => 1 );
has test_port   => ( is => 'ro', isa => PositiveInt, required => 1 );
has test_scheme => ( is => 'ro', isa => Str,         default  => q[] );
has timeout     => ( is => 'ro', isa => Int,         default  => 5 );

no Pcore;

our $TEST_SCHEME = {
    http  => [ [ 'www.google.com', 80 ],  \&_test_http, ],
    https => [ [ 'www.google.com', 443 ], \&_test_http, ],
    whois => [ [ 'whois.iana.org', 43 ],  \&_test_whois, ],
};

sub check ( $self, %args ) {
    $args{proxy} = Pcore::Proxy->new( $args{proxy} ) if !ref $args{proxy};

    return $self->new( \%args )->_run;
}

sub _run ($self) {
    state $supported_types = [ $PROXY_HTTP, $PROXY_CONNECT, $PROXY_SOCKS5 ];

    # proxy type is not supported
    return $self->_finish(0) unless $self->proxy_type ~~ $supported_types;

    if ( $self->proxy_type == $PROXY_HTTP ) {
        $self->_check_http_proxy;
    }
    else {
        $self->_check_tunnel_proxy;
    }

    return;
}

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
        return $self->_finish(0);
    }

    # test connect to the proxy
    $self->{h} = Pcore::AE::Handle->new(
        connect         => [ $self->proxy->host->name, $self->proxy->port ],
        connect_timeout => $self->timeout,
        timeout         => $self->timeout,

        # TODO disable proxy
        on_connect_error => sub ( $h, $message ) {
            $self->_finish(0);

            return;
        },
        on_error => sub ( $h, $fatal, $message ) {
            $self->_finish(0);

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
            $self->_finish(1);

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
            $self->_finish(0);

            return;
        },
        on_connect_error => sub ( $h, $message ) {
            $self->_finish(0);

            return;
        },
        on_connect => sub ( $h, @ ) {
            $test->($self);

            return;
        },
    );

    return;
}

sub _finish ( $self, $status ) {
    $self->{h}->destroy if $self->{h};

    $self->cb->($status);

    return;
}

sub _test_http ($self) {
    state $req_http_http = q[GET http://www.google.com/favicon.ico HTTP/1.0] . $CRLF . $CRLF;

    state $req_http_https = q[GET https://www.google.com/favicon.ico HTTP/1.0] . $CRLF . $CRLF;

    state $req_tunnel = qq[GET /favicon.ico HTTP/1.1${CRLF}Host: www.google.com${CRLF}${CRLF}];

    if ( $self->proxy_type == $PROXY_HTTP ) {
        $self->{h}->push_write( $self->test_scheme eq 'http' ? $req_http_http : $req_http_https );
    }
    else {
        $self->{h}->starttls('connect') if $self->test_scheme eq 'https';

        $self->{h}->push_write($req_tunnel);
    }

    $self->{h}->read_http_res_headers(
        headers => 0,
        sub ( $h, $res, $error_reason ) {
            if ( $error_reason || $res->{status} != 200 ) {    # headers parsing error
                $self->_finish(0);
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
                            $self->_finish(1);
                        }
                        else {
                            $self->_finish(0);
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
sub _test_whois ($self) {
    $self->_finish(0);

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 202                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
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
