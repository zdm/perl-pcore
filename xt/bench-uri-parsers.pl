#!/usr/bin/env perl

package main v0.1.0;

use Pcore -const;
use Benchmark qw[];
use URI qw[];
use Mojo::URL qw[];

const our $COUNT => -3;

my $uri = q[path/path];

my $base = q[http://];

my $base_obj = P->uri($base);

# initialize
say URI->new_abs( $uri, $base );

say Mojo::URL->new($uri)->to_abs( Mojo::URL->new($base) );

say P->uri( $uri, base => $base_obj );

my $tests = {
    URI => sub {
        my $u = URI->new($uri) . $EMPTY;

        # my $u = URI->new_abs( $uri, $base ) . $EMPTY;

        return;
    },
    'Mojo::URL' => sub {
        my $u = Mojo::URL->new($uri) . $EMPTY;

        # my $u = Mojo::URL->new($uri)->to_abs( Mojo::URL->new($base) ) . $EMPTY;

        return;
    },
    'Pcore::Util::URI' => sub {
        my $u = P->uri($uri) . $EMPTY;

        # my $u = P->uri( $uri, base => $base_obj ) . $EMPTY;

        return;
    },
};

Benchmark::cmpthese( Benchmark::timethese( $COUNT, $tests ) );

1;
__END__
=pod

=encoding utf8

=cut
