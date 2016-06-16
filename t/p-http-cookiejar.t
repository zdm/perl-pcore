#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Test::More;
use Pcore::HTTP::CookieJar;

my $test_data = {
    set_cover_domain => [    #
        [ 'www.aaa.ru', '.aaa.ru',      1 ],    # allow to set cover cookie to !pub. suffix
        [ 'www.aaa.ru', '.www.aaa.ru',  1 ],    # allow to set cover cookie to !pub. suffix
        [ 'www.aaa.ru', '.ru',          0 ],
        [ 'www.aaa.ru', 'bbb.ru',       0 ],    # permit to set cover cookie to not cover domain
        [ 'www.aaa.ru', 'a.www.aaa.ru', 0 ],    # permit to set cover cookie to not cover domain

        [ 'www.ck', 'ck',      0 ],             # permit to set cover cookie to pub. suffix
        [ 'www.ck', '.www.ck', 1 ],             # alow to set cover cookie

        # set cover cookie from pub. suffix url
        [ 'aaa.ck', '.ck',     0 ],             # permit to set cover cookie to pub. suffix
        [ 'aaa.ck', '.aaa.ck', 0 ],             # permit to set cover cookie from pub. suffix
        [ 'aaa.ck', 'aaa.ck',  1 ],             # allow to set origin cookie from pub. suffix
    ],
};

our $TESTS = $test_data->{set_cover_domain}->@*;

plan tests => $TESTS;

# set cover domain
for my $args ( $test_data->{set_cover_domain}->@* ) {
    state $i = 0;

    my $c = Pcore::HTTP::CookieJar->new;

    $c->parse_cookies( 'http://' . $args->[0], ["1=2;domain=$args->[1]"] );

    unless ( ( exists $c->{cookies}->{ $args->[1] } ? 1 : 0 ) == $args->[2] ) {
        say {$STDERR_UTF8} dump $c->{cookies};
    }

    ok( ( exists $c->{cookies}->{ $args->[1] } ? 1 : 0 ) == $args->[2], 'set_cover_domain_' . $i++ . '_' . $args->[1] );
}

done_testing $TESTS;

1;
__END__
=pod

=encoding utf8

=cut
