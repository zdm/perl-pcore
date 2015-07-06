package Pcore::AnyEvent::Proxy::Source::WorldOfProxy;

use Pcore qw[-class];

with qw[Pcore::AnyEvent::Proxy::Source];

has api_key      => ( is => 'ro', isa => Str,         required => 1 );
has http_timeout => ( is => 'ro', isa => PositiveInt, default  => 10 );

has _urls => ( is => 'lazy', isa => HashRef, init_arg => undef );

no Pcore;

sub _build__urls {
    my $self = shift;

    return {
        'http://worldofproxy.com/getx_' . $self->api_key . '_0_______.html' => { http   => 1 },
        'http://worldofproxy.com/getx_' . $self->api_key . '_1_______.html' => { https  => 1 },
        'http://worldofproxy.com/getx_' . $self->api_key . '_3_______.html' => { socks4 => 1 },
        'http://worldofproxy.com/getx_' . $self->api_key . '_4_______.html' => { socks5 => 1 },
    };
}

sub load {
    my $self    = shift;
    my $cv      = shift;
    my $proxies = shift;

    for my $url ( keys $self->_urls->%* ) {
        P->ua->request(
            $url,
            timeout   => $self->http_timeout,
            blocking  => $cv,
            on_finish => sub ($res) {
                if ( $res->status == 200 && $res->has_body ) {
                    P->text->decode_eol( $res->body );

                    for my $addr ( split /\n/sm, $res->body->$* ) {
                        push $proxies, { $self->_urls->{$url}->%*, addr => $addr };
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
## │    3 │ 30, 40               │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
