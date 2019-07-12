#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Pcore::Lib::Hash::LRU;
use Tie::Hash::LRU;
use Cache::LRU;
use Benchmark;

my $NUM = 1000;

my $lru = tie my %lru, 'Tie::Hash::LRU', $NUM;

# for ( 1 .. 120 ) {
#     $lru{$_} = undef;
# }
#
# say dump \%lru;

my $limited = Pcore::Lib::Hash::LRU->new($NUM);

# for ( 1 .. 120 ) {
#     $limited->{$_} = undef;
# }
#
# say dump $limited;

my $cache_lru = Cache::LRU->new( size => $NUM );

# for ( 1 .. 120 ) {
#     $cache_lru->set( $_ => undef );
# }
#
# say dump $cache_lru;

my $t = {
    lru => sub {
        state $i = 1000;

        $lru{ $i++ } = undef;
    },
    limited => sub {
        state $i = 1000;

        $limited->{ $i++ } = undef;

        return;
    },
    cache_lru => sub {
        state $i = 1000;

        $cache_lru->set( $i++ => undef );

        return;
    }
};

Benchmark::cmpthese( Benchmark::timethese( -3, $t ) );

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 13                   | Miscellanea::ProhibitTies - Tied variable used                                                                 |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
