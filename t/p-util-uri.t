#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Test::More;

our $tests = [

    # parsing
    ['http://user:password@host:9999/path?query=123#fragment'] => 'http://user:password@host:9999/path?query=123#fragment',
    ['//host:9999/path/']                                      => '//host:9999/path/',
    ['./path:path']                                            => './path:path',
    ['scheme:./path:path']                                     => 'scheme:path:path',

    # parsing with base
    [ '//host:9999/path/', 'http://' ]                     => 'http://host:9999/path/',
    [ '//host:9999/path/', 'http://base_host/base_path/' ] => 'http://host:9999/path/',
    [ '/path/path/',       'http://base-host/base_path/' ] => 'http://base-host/path/path/',
    [ '/base_path/path/',  'http://base_host/base_path/' ] => 'http://base_host/base_path/path/',
    [ 'path/path/',        'http://base_host/base_path/' ] => 'http://base_host/base_path/path/path/',

    # file path
    ['file://user:password@host:9999/path?query=123#fragment'] => 'file://user:password@host:9999/path?query=123#fragment',
    [ '//user:password@host:9999/path?query=123#fragment', 'file://' ]           => 'file://user:password@host:9999/path?query=123#fragment',
    [ 'path/path',                                         'file://' ]           => 'file:path/path',
    [ 'path/path',                                         'file:///base_path' ] => 'file:/path/path',

    # inherit
    [ 'path/path?q#f', 'http://host/path/?bq#bf' ] => 'http://host/path/path/path?q=#f',
    [ 'path/path#f',   'http://host/path/?bq#bf' ] => 'http://host/path/path/path#f',
    [ 'path/path?q',   'http://host/path/?bq#bf' ] => 'http://host/path/path/path?q=',

    [ '?q#f', 'http://host/path/?bq#bf' ] => 'http://host/path/?q=#f',
    [ '?q',   'http://host/path/?bq#bf' ] => 'http://host/path/?q=',
    [ '#f',   'http://host/path/?bq#bf' ] => 'http://host/path/?bq=#f',

    # mailto
    [ 'user@host', 'mailto:' ] => 'mailto:user@host',

    # IDN
    ['http://президент.ua'] => 'http://xn--d1abbgf6aiiy.ua',
];

our $TESTS = $tests->@* / 2;

plan tests => $TESTS;

my $i;

for my $pair ( P->list->pairs( $tests->@* ) ) {
    my $uri = P->uri( $pair->key->@* );

    # require URI;
    #
    # my $uri_uri = $pair->key->@* > 1 ? URI->new_abs( $pair->key->@* ) : URI->new( $pair->key->@* );
    #
    # say 'URI: ' . $uri->to_string . ' ne ' . $uri_uri->as_string if $uri->to_string ne $uri_uri->as_string;
    #
    # say $pair->value;
    # say $uri->to_string;

    ok( $uri->to_string eq $pair->value, 'p_util_uri_' . ++$i );
}

done_testing $TESTS;

1;
__END__
=pod

=encoding utf8

=cut
