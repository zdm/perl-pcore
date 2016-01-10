package Pcore::AE::Handle::ProxyPool::Source::WorldOfProxy;

use Pcore -class;
use Pcore::Util::Text qw[decode_eol];

with qw[Pcore::AE::Handle::ProxyPool::Source];

has api_key      => ( is => 'ro', isa => Str,         required => 1 );
has http_timeout => ( is => 'ro', isa => PositiveInt, default  => 10 );

has _urls => ( is => 'lazy', isa => HashRef, init_arg => undef );

sub _build__urls {
    my $self = shift;

    return {
        http    => 'http://worldofproxy.com/getx_' . $self->api_key . '_0_______.html',
        connect => 'http://worldofproxy.com/getx_' . $self->api_key . '_1_______.html',
        socks5  => 'http://worldofproxy.com/getx_' . $self->api_key . '_4_______.html',
        socks4  => 'http://worldofproxy.com/getx_' . $self->api_key . '_3_______.html',
    };
}

sub load ( $self, $cb ) {
    my $proxies;

    my $cv = AE::cv {
        $cb->($proxies);

        return;
    };

    for my $url ( values $self->_urls->%* ) {
        P->http->get(
            $url,
            timeout   => $self->http_timeout,
            cv        => $cv,
            on_finish => sub ($res) {
                if ( $res->status == 200 && $res->has_body ) {
                    decode_eol $res->body->$*;

                    for my $addr ( split /\n/sm, $res->body->$* ) {
                        push $proxies, $addr;
                    }
                }

                return;
            }
        );
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 33                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Handle::ProxyPool::Source::WorldOfProxy

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
