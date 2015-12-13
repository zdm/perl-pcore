#!/usr/bin/env perl

package Str1;

use Pcore qw[-class];

use overload    #
  q[""] => sub {
    return $_[0]->val;
  },
  q[.] => sub {
    my $val = $_[0]->val;

    if ( !$_[2] ) {
        return $val . q[/] . $_[1];
    }
    else {
        return $_[1] . q[/] . $val;
    }
  },
  fallback => undef;

has val => ( is => 'ro', isa => Str, required => 1 );

no Pcore;

1;

package Str2;

use Pcore qw[-class];

use overload    #
  q[""] => sub {
    return $_[0]->val;
  },
  fallback => undef;

has val => ( is => 'ro', isa => Str, required => 1 );

no Pcore;

1;

package main v0.1.0;

use Pcore;
use Benchmark;

my $s1 = Str1->new( { val => 'мама' } );

my $s2 = Str2->new( { val => 'мама' } );

my $tests = {
    overload => sub {
        return $s1 . 'text';
    },
    no_overload => sub {
        return $s2 . 'text';
    },
};

say $tests->{overload}->();
say $tests->{no_overload}->();

Benchmark::cmpthese( Benchmark::timethese( -3, $tests ) );

1;
__END__
=pod

=encoding utf8

=cut
