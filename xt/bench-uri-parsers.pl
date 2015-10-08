#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Const::Fast qw[];
use Benchmark qw[];
use URI qw[];
use Mojo::URL qw[];

Const::Fast::const our $COUNT => -3;

my $uri = q[/aaa/];

my $base = q[http://base_host/base_path/];

my $base_obj = P->uri($base);

# initialize
say URI->new_abs( $uri, $base );

say Mojo::URL->new($uri)->to_abs( Mojo::URL->new($base) );

say P->uri( $uri, base => $base );

my $tests = {
    URI => sub {
        my $u = URI->new_abs( $uri, $base );

        return;
    },
    'Mojo::URL' => sub {
        my $u = Mojo::URL->new($uri)->to_abs( Mojo::URL->new($base) );

        return;
    },
    'Pcore::Util::URI' => sub {
        my $u = P->uri( $uri, base => $base );

        return;
    },
};

Benchmark::cmpthese( Benchmark::timethese( $COUNT, $tests ) );

1;
__END__
=pod

=encoding utf8

=head1 REQUIRED ARGUMENTS

=over

=back

=head1 OPTIONS

=over

=back

=cut
