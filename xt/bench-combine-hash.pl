#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Benchmark;

my $a = { map { $_ => 1 } 1 .. 100_000 };

my $b = { map { $_ => 1 } 1 .. 1_000 };

my $tests = {
    for => sub {
        my $c = {};

        for ( keys $b->%* ) {
            $c->{$_} = $b->{$_};
        }

        return $c;
    },
    internal1 => sub {
        my $c = {};

        $c = { $c->%*, $b->%* };

        return $c;
    },
    internal2 => sub {
        my $c = {};

        $c->@{ keys $b->%* } = values $b->%*;

        return $c;
    },
};

# say dump $tests->{for}->();
# say dump $tests->{internal1}->();
# say dump $tests->{internal2}->();

Benchmark::cmpthese( Benchmark::timethese( -3, $tests ) );

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 16, 25, 32           | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
