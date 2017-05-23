#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Benchmark;
use Pcore::HTTP::Cookies;

# use HTTP::Cookie;

my $uri = P->uri('http://aaa.bbb.com/path/');

my $cookies = [    #
    'name1=value; domain=aaa.bbb.com; path=/',
    'name2=value; domain=aaa.bbb.com; path=/',
    'name3=value; domain=aaa.bbb.com; path=/',
    'name4=value; domain=aaa.bbb.com; path=/',
    'name5=value; domain=aaa.bbb.com; path=/',
];

my $jar = Pcore::HTTP::Cookies->new;

my $tests = {
    add => sub {
        $jar->parse_cookies( $uri, $cookies );

        return;
    },
};

Benchmark::cmpthese( Benchmark::timethese( -3, $tests ) );

1;
__END__
=pod

=encoding utf8

=cut
