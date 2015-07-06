#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Test::More;
use Pcore::AnyEvent::Proxy::Pool;

our $PROXIES = [
    { addr => '127.0.0.1:80' } => {
        is_http    => 1,
        is_https   => 0,
        is_socks   => 0,
        is_socks5  => 0,
        is_socks4  => 0,
        is_socks4a => 0,
    },
    { addr => 'http://127.0.0.1:80' } => {
        is_http    => 1,
        is_https   => 0,
        is_socks   => 0,
        is_socks5  => 0,
        is_socks4  => 0,
        is_socks4a => 0,
    },
    { addr => 'https://127.0.0.1:80' } => {
        is_http    => 0,
        is_https   => 1,
        is_socks   => 0,
        is_socks5  => 0,
        is_socks4  => 0,
        is_socks4a => 0,
    },
    { addr => 'socks://127.0.0.1:80' } => {
        is_http    => 0,
        is_https   => 0,
        is_socks   => 1,
        is_socks5  => 1,
        is_socks4  => 1,
        is_socks4a => 1,
    },
    { addr => 'socks5://127.0.0.1:80' } => {
        is_http    => 0,
        is_https   => 0,
        is_socks   => 1,
        is_socks5  => 1,
        is_socks4  => 0,
        is_socks4a => 0,
    },
    { addr => '127.0.0.1:80', http => 1, socks => 1 } => {
        is_http    => 1,
        is_https   => 0,
        is_socks   => 1,
        is_socks5  => 1,
        is_socks4  => 1,
        is_socks4a => 1,
    },
];

my $tests_num = 0;

for my $pair ( P->list->pairs( $PROXIES->@* ) ) {
    $tests_num += keys $pair->value->%*;
}

our $TESTS = $tests_num;

plan tests => $TESTS;

for my $pair ( P->list->pairs( $PROXIES->@* ) ) {
    my $proxy = new_proxy( $pair->key );

    for my $method ( sort keys $pair->value->%* ) {
        ok( $proxy->$method == $pair->value->{$method}, $pair->key->{addr} . q[_] . $method . q[_] . $pair->value->{$method} );
    }
}

done_testing $TESTS;

sub new_proxy {
    my $args = shift;

    my $pool = Pcore::AnyEvent::Proxy::Pool->new(
        source => [
            {   class   => 'List',
                proxies => [ { $args->%* } ],
            }
        ],
    );

    return $pool->get_proxy( list => 'http' ) // $pool->get_proxy( list => 'https' );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 63, 73, 86           │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
