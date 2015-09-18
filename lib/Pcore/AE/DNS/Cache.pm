package Pcore::AE::DNS::Cache;

use Pcore;
use base qw[AnyEvent::DNS];
use AnyEvent::Socket qw[];

our $TTL          = 60;
our $NEGATIVE_TTL = 1;

our $_CACHE_DNS      = {};
our $_CACHE_SOCKADDR = {};
our $_OLD_DNS_RESOLVER;
our $_EXPIRE_TIMER;

*AnyEvent::Socket::resolve_sockaddr_nocache = \&AnyEvent::Socket::resolve_sockaddr;

sub AnyEvent::Socket::resolve_sockaddr_cache {
    state $calback = {};

    my $cache_key = join q[-], map { $_ // q[] } @_;

    push $calback->{$cache_key}->@*, pop;

    return if $calback->{$cache_key}->@* > 1;

    if ( exists $_CACHE_SOCKADDR->{$cache_key} ) {
        if ( $_CACHE_SOCKADDR->{$cache_key}->[0] > time ) {
            while ( my $cb = shift $calback->{$cache_key} ) {
                $cb->( $_CACHE_SOCKADDR->{$cache_key}->[1]->@* );
            }

            delete $calback->{$cache_key};

            return;
        }
        else {
            delete $_CACHE_SOCKADDR->{$cache_key};
        }
    }

    AnyEvent::Socket::resolve_sockaddr_nocache(
        @_,
        sub {
            $_CACHE_SOCKADDR->{$cache_key}->[0] = time + ( @_ ? $TTL : $NEGATIVE_TTL );

            $_CACHE_SOCKADDR->{$cache_key}->[1] = [@_];

            while ( my $cb = shift $calback->{$cache_key} ) {
                $cb->( $_CACHE_SOCKADDR->{$cache_key}->[1]->@* );
            }

            delete $calback->{$cache_key};

            return;
        }
    );

    return;
}

sub register ( $self, %args ) {
    return if $AnyEvent::DNS::RESOLVER && ref $AnyEvent::DNS::RESOLVER eq $self;

    $_OLD_DNS_RESOLVER = $AnyEvent::DNS::RESOLVER;

    # use google DNS servers for ipv4 and ipv6 by default
    $args{server} = \@AnyEvent::DNS::DNS_FALLBACK if !$args{server};

    $AnyEvent::DNS::RESOLVER = $self->new(%args);

    my $expire_timeout = ( $TTL > $NEGATIVE_TTL ? $TTL : $NEGATIVE_TTL ) * 2;

    $expire_timeout = 60 if $expire_timeout < 60;

    $_EXPIRE_TIMER = AE::timer $expire_timeout, $expire_timeout, sub {
        $self->expire;

        return;
    };

    # install resolve_sockaddr hook
    {
        no warnings qw[redefine prototype];

        *AnyEvent::Socket::resolve_sockaddr = \&AnyEvent::Socket::resolve_sockaddr_cache;
    }

    return;
}

sub unregister ($self) {
    $AnyEvent::DNS::RESOLVER = $_OLD_DNS_RESOLVER;

    undef $_EXPIRE_TIMER;

    # remove resolve_sockaddr hook
    {
        no warnings qw[redefine prototype];

        *AnyEvent::Socket::resolve_sockaddr = *AnyEvent::Socket::resolve_sockaddr_nocache;
    }

    return;
}

sub purge ($self) {
    $_CACHE_DNS->%* = ();

    $_CACHE_SOCKADDR->%* = ();

    return;
}

sub expire ($self) {
    my $time = time;

    for ( keys $_CACHE_DNS->%* ) {
        delete $_CACHE_DNS->{$_} if $_CACHE_DNS->{$_}->[0] <= $time;
    }

    for ( keys $_CACHE_SOCKADDR->%* ) {
        delete $_CACHE_SOCKADDR->{$_} if $_CACHE_SOCKADDR->{$_}->[0] <= $time;
    }

    return;
}

sub request ( $self, $req, $cb ) {
    state $calback = {};

    my $cache_key = join q[-], $req->{qd}->[0]->@*;

    push $calback->{$cache_key}->@*, $cb;

    return if $calback->{$cache_key}->@* > 1;

    if ( exists $_CACHE_DNS->{$cache_key} ) {
        if ( $_CACHE_DNS->{$cache_key}->[0] > time ) {
            while ( my $cb = shift $calback->{$cache_key} ) {
                $cb->( $_CACHE_DNS->{$cache_key}->[1]->@* );
            }

            delete $calback->{$cache_key};

            return;
        }
        else {
            delete $_CACHE_DNS->{$cache_key};
        }
    }

    $self->SUPER::request(
        $req,
        sub {
            $_CACHE_DNS->{$cache_key}->[0] = time + ( @_ ? $TTL : $NEGATIVE_TTL );

            $_CACHE_DNS->{$cache_key}->[1] = [@_];

            while ( my $cb = shift $calback->{$cache_key} ) {
                $cb->( $_CACHE_DNS->{$cache_key}->[1]->@* );
            }

            delete $calback->{$cache_key};

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
## │    3 │ 107, 109, 117, 121   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::DNS::Cache

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
