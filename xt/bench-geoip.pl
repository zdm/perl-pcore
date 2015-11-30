#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Benchmark qw[];

my $tests = {
    pp => sub {
        state $init = 0;

        if ( $init <= 1 ) {
            $init++;

            $Pcore::Util::GeoIP::GEOIP_PURE_PERL = 1;

            P->geoip->reconnect;

            1;
        }

        P->geoip->country_code_by_addr('192.37.51.100');

        return;
    },
    xs => sub {
        state $init = 0;

        if ( $init <= 1 ) {
            $init++;

            $Pcore::Util::GeoIP::GEOIP_PURE_PERL = 0;

            P->geoip->reconnect;

            1;
        }

        P->geoip->country_code_by_addr('192.37.51.100');

        return;
    },
};

Benchmark::cmpthese( Benchmark::timethese( -3, $tests ) );

1;
__END__
=pod

=encoding utf8

=cut
