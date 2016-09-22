#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Benchmark;
use Crypt::Argon2;

my $rand = '1' x 32;

my $res;

for my $n ( 1, 3, 10 ) {
    for my $m ( '64M', '512M', '1G' ) {
        for my $p ( 1, P->sys->cpus_num, P->sys->cpus_num * 2 ) {
            my $id = "$n-$m-$p";

            my $t = Benchmark::timeit(
                3,
                sub {
                    my $hash = Crypt::Argon2::argon2i_pass( $rand, $rand, $n, $m, $p, 32 );

                    return $hash;
                }
            );

            say "$id - " . timestr $t;

            $res->{$id} = $t;
        }
    }
}

1;
__END__
=pod

=encoding utf8

=cut
