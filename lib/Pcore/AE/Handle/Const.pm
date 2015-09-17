package Pcore::AE::Handle::Const;

use Pcore qw[-export];
use Const::Fast qw[const];

our @EXPORT_OK   = qw[$PROXY_TYPE_HTTP $PROXY_TYPE_CONNECT $PROXY_TYPE_SOCKS $PROXY_TYPE_SOCKS5 $PROXY_TYPE_SOCKS4 $PROXY_TYPE_SOCKS4A $PROXY_ERROR_TUNNEL $PROXY_ERROR_CONNECT $PROXY_ERROR_OTHER];
our %EXPORT_TAGS = (
    PROXY_TYPE  => [qw[$PROXY_TYPE_HTTP $PROXY_TYPE_CONNECT $PROXY_TYPE_SOCKS $PROXY_TYPE_SOCKS5 $PROXY_TYPE_SOCKS4 $PROXY_TYPE_SOCKS4A]],
    PROXY_ERROR => [qw[$PROXY_ERROR_TUNNEL $PROXY_ERROR_CONNECT $PROXY_ERROR_OTHER]],
);
our @EXPORT = ();

const our $PROXY_ERROR_TUNNEL  => 1;    # error creating tunnel to the destination, destination host:port not respond or banned on proxy server
const our $PROXY_ERROR_CONNECT => 2;    # can't establish connection to the proxy host:port
const our $PROXY_ERROR_OTHER   => 5;    # proxy protocol error, invalid proxy type / auth error, etc ...

const our $PROXY_TYPE_HTTP    => 1;
const our $PROXY_TYPE_CONNECT => 2;
const our $PROXY_TYPE_SOCKS   => 3;
const our $PROXY_TYPE_SOCKS5  => 31;
const our $PROXY_TYPE_SOCKS4  => 32;
const our $PROXY_TYPE_SOCKS4A => 33;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Handle::Const

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
