#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Benchmark qw[];

say dump P->geoip->country->record_for_address('192.37.51.100');
say dump P->geoip->country->record_for_address('46.219.212.109')->{country}->{iso_code};

# exit;

my $tests = {
    'MaxMind::DB::Reader' => sub {
        P->geoip->country->record_for_address('46.219.212.109');

        return;
    },
};

Benchmark::cmpthese( Benchmark::timethese( -3, $tests ) );

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 9                    | ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
