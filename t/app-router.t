#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Test::More;
use Pcore::App::Router;
use Pcore::Util::List qw[pairs];

my $t = [
    AAA    => 'aaa',
    AaaBbb => 'aaa-bbb',
    AAABbb => 'aaa-bbb',
    aaaBbb => 'aaa-bbb',
    aaaBBB => 'aaa-bbb',

    'aaaBBB/CccDDEee' => 'aaa-bbb/ccc-dd-eee',
];

our $TESTS = $t->@* / 2;

plan tests => $TESTS;

for my $test ( pairs $t->@* ) {
    my $out = Pcore::App::Router::_perl_class_path_to_snake_case( $test->[0] );

    cluck "$test->[0] -> $out = ERROR, expect $test->[1]" if $out ne $test->[1];

    ok( $out eq $test->[1], "$test->[0] -> $out" );
}

done_testing $TESTS;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 25                   | Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
