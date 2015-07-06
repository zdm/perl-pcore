package Pcore::AnyEvent::Proxy::Source::Tor;

use Pcore qw[-class];
use IO::Socket::INET;

with qw[Pcore::AnyEvent::Proxy::Source];

has host         => ( is => 'ro', isa => Str,         default   => '127.0.0.1' );
has port         => ( is => 'ro', isa => PositiveInt, default   => 9050 );
has control_port => ( is => 'ro', isa => PositiveInt, default   => 9051 );
has password     => ( is => 'ro', isa => Str,         predicate => 1 );

no Pcore;

# NOTE it's important to use "persistent" = 0 in AnyEvent::HTTP, otherwise all connections will not use NEWNYM, if NYM changed

sub load {
    my $self    = shift;
    my $cv      = shift;
    my $proxies = shift;

    $cv->begin;

    push $proxies, { addr => $self->host . q[:] . $self->port, socks5 => 1 };

    $cv->end;

    return;
}

sub update_proxy_status {
    my $self  = shift;
    my $proxy = shift;

    # don't ban proxy, get new identity instead
    if ( $proxy->is_banned ) {
        $self->new_identity;

        $proxy->_set_is_banned(0);

        return;
    }

    $self->_pool->update_proxy_status($proxy);

    return;
}

sub id {
    my $self = shift;

    return $self->_id;
}

sub new_identity {
    my $self = shift;

    my $socket = IO::Socket::INET->new(
        PeerAddr => $self->host,
        PeerPort => $self->control_port,
        Proto    => 'tcp'
    ) or die;

    my $password = $self->has_password ? $self->password : q[];

    print {$socket} qq[AUTHENTICATE "$password"${CRLF}SIGNAL NEWNYM${CRLF}QUIT${CRLF}];

    $socket->close;

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
