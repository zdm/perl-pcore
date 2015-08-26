#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Test::More;

our $tests = [

    # parsing
    [q[http://user:password@host:9999/path?query=123#fragment]] => q[http://user:password@host:9999/path?query=123#fragment],
    [q[//host:9999/path/]]                                      => q[//host:9999/path/],

    # parsing with base
    [ q[//host:9999/path/], q[http://] ]                     => q[http://host:9999/path/],
    [ q[//host:9999/path/], q[http://base_host/base_path/] ] => q[http://host:9999/path/],
    [ q[/path/path/],       q[http://base-host/base_path/] ] => q[http://base-host/path/path/],
    [ q[/base_path/path/],  q[http://base_host/base_path/] ] => q[http://base_host/base_path/path/],
    [ q[path/path/],        q[http://base_host/base_path/] ] => q[http://base_host/base_path/path/path/],

    # file path
    [q[file://user:password@host:9999/path?query=123#fragment]] => q[file://user:password@host:9999/path?query=123#fragment],
    [ q[//user:password@host:9999/path?query=123#fragment], q[file://] ]           => q[file://user:password@host:9999/path?query=123#fragment],
    [ q[path/path],                                         q[file://] ]           => q[file:path/path],
    [ q[path/path],                                         q[file:///base_path] ] => q[file:/path/path],

    # inherit
    [ q[path/path?q#f], q[http://host/path/?bq#bf] ] => q[http://host/path/path/path?q=#f],
    [ q[path/path#f],   q[http://host/path/?bq#bf] ] => q[http://host/path/path/path#f],
    [ q[path/path?q],   q[http://host/path/?bq#bf] ] => q[http://host/path/path/path?q=],

    [ q[?q#f], q[http://host/path/?bq#bf] ] => q[http://host/path/?q=#f],
    [ q[?q],   q[http://host/path/?bq#bf] ] => q[http://host/path/?q=],
    [ q[#f],   q[http://host/path/?bq#bf] ] => q[http://host/path/?bq=#f],

    # mailto
    [ q[user@host], q[mailto:buser@bhost] ] => q[mailto://user@host],
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
    # say 'URI: ' . $uri->to_string . q[ ne ] . $uri_uri->as_string if $uri->to_string ne $uri_uri->as_string;
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
