package Pcore::AnyEvent::Handle::Proxy;

use Pcore qw[-class];
use Pcore::AnyEvent::Handle;

has cb => ( is => 'ro', isa => CodeRef, required => 1 );
has proxy => ( is => 'ro', isa => InstanceOf ['Pcore::Proxy'], required => 1 );
has proxy_type => ( is => 'ro', isa => Enum [qw[http connect socks5 socks4 socks4a]], required => 1 );
has test_scheme => ( is => 'ro', isa => Str,         required => 1 );
has test_host   => ( is => 'ro', isa => Str,         required => 1 );
has test_port   => ( is => 'ro', isa => PositiveInt, required => 1 );

has proxy_type_is_supported => ( is => 'lazy', isa => Bool, init_arg => undef );
has proxy_is_http           => ( is => 'lazy', isa => Bool, init_arg => undef );

no Pcore;

our $TEST_SCHEME = {
    http  => [ [ 'google.com',     80 ],  \&_test_http, ],
    https => [ [ 'google.com',     443 ], \&_test_http, ],
    whois => [ [ 'whois.iana.org', 43 ],  \&_test_whois, ],
};

sub check ( $self, %args ) {
    $args{proxy} = Pcore::Proxy->new( $args{proxy} ) if !ref $args{proxy};

    return $self->new( \%args )->_run;
}

sub _build_proxy_type_is_supported ($self) {
    return $self->proxy_type ~~ [qw[http connect socks5]] ? 1 : 0;
}

sub _build_proxy_is_tunnel ($self) {
    return $self->proxy_type eq 'http' ? 1 : 0;
}

sub _run ($self) {

    # proxy type is not supported
    return $self->_finish(0) if !$self->proxy_type_is_supported;

    if ( $self->proxy_is_http ) {
        $self->_check_http_proxy;
    }
    else {
        $self->_check_tunnel_proxy;
    }

    return;
}

sub _check_http_proxy ($self) {
    my $connect;

    my $test;

    if ( $self->test_scheme eq 'http' ) {
        $connect = $TEST_SCHEME->{http}->[0];

        $test = $TEST_SCHEME->{http}->[1];
    }
    elsif ( $self->test_scheme eq 'https' ) {
        $connect = $TEST_SCHEME->{https}->[0];

        $test = $TEST_SCHEME->{https}->[1];
    }
    else {
        # http proxy can work only with http or https schemes
        return $self->_finish(0);
    }

    # test connect to the proxy
    $self->{h} = Pcore::AnyEvent::Handle->new(
        connect => $connect,

        # TODO disable proxy
        on_connect_error => sub () {
            $self->_finis(0);

            return;
        },
        on_error => sub ( $h, $fatal, $message ) {
            $self->_finis(0);

            return;
        },
        on_connect => sub ( $h, @ ) {
            $test->(
                $h,
                sub ($status) {
                    $self->_finish($status);

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub _check_tunnel_proxy ($self) {

    return;
}

sub _finish ( $self, $status ) {
    $self->cb->($status);

    return;
}

sub _test_http ( $h, $cb ) {
    state $req = qq[GET /favicon.ico HTTP/1.1${CRLF}Host: www.google.com${CRLF}${CRLF}];

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
}

# TODO
sub _test_whois ( $h, $cb ) {
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
## │    2 │ 139                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AnyEvent::Handle::Proxy

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
