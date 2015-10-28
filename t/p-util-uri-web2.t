#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Test::More;

our $TESTS = [    #
    [ 'tumblr.com',                  'web2_id', q[] ],
    [ 'aaa.tumblr.com',              'web2_id', q[tumblr.com] ],
    [ 'bbb.aaa.tumblr.com',          'web2_id', q[] ],
    [ 'www.aaa.tumblr.com',          'web2_id', q[tumblr.com] ],
    [ 'blogspot.com/path',           'web2_id', q[] ],
    [ 'www.blogspot.com/path',       'web2_id', q[] ],
    [ 'aaa.blogspot.com/path',       'web2_id', q[blogspot] ],
    [ 'blogspot.co.uk/path',         'web2_id', q[] ],
    [ 'www.blogspot.co.uk/path',     'web2_id', q[] ],
    [ 'aaa.blogspot.co.uk/path',     'web2_id', q[blogspot] ],
    [ 'www.blogspot.co.uk.tld/path', 'web2_id', q[] ],
    [ 'aaa.blogspot.co.uk.tld/path', 'web2_id', q[] ],
    [ 'twitter.com/path',            'web2_id', q[twitter.com] ],
    [ 'www.twitter.com/path',        'web2_id', q[twitter.com] ],
    [ 'aaa.twitter.com/path',        'web2_id', q[] ],
    [ 'twitter.com/path/subpath',    'web2_id', q[twitter.com] ],

    #
    [ 'aaa.twitter.com/path', 'is_web2',       1 ],
    [ 'aaa.twitter.com/path', 'is_web2_valid', 0 ],
];

plan tests => scalar $TESTS->@*;

my $i;

for my $test ( $TESTS->@* ) {
    my $method = $test->[1];

    my $uri = P->uri( $test->[0], base => 'http://', authority => 1 );

    say dump $uri->_web2_parsed if !ok( $uri->$method eq $test->[2], $i++ . q[_] . $test->[0] );
}

done_testing scalar $TESTS->@*;

1;
__END__
=pod

=encoding utf8

=cut
