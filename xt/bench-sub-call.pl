#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Benchmark;

my @args = ( 1, 2, 3 );

sub sub1 {
    return;
}

my $proxy_tests = {
    'sub(@_)' => sub {    # static function, new stack
        sub1(@_);

        return;
    },
    'sub @_' => sub {     # static function, new stack, checked at compile time
        sub1 @_;

        return;
    },
    '&sub' => sub {       # static function, reuse stack
        &sub1;            ## no critic qw[Subroutines::ProhibitAmpersandSigils]

        return;
    },
    'goto &sub' => sub {
        goto &sub1;
    },
};

my $call_tests = {
    'sub(@args)' => sub {    # static function, new stack
        sub1( 1, 2, 3, 4 );

        return;
    },
    'sub @args' => sub {     # static function, new stack, checked at compile time
        sub1 1, 2, 3, 4;

        return;
    },
    '&sub(@args)' => sub {    # static function, reuse stack
        &sub1( 1, 2, 3, 4 );    ## no critic qw[Subroutines::ProhibitAmpersandSigils]

        return;
    },
};

my $method_tests = {
    '->method(@_)' => sub {     # static function, new stack
        main->sub1(@_);

        return;
    },
    'method( $self, @_ )' => sub {    # static function, new stack, checked at compile time
        sub1( 'main', @_ );

        return;
    },
};

Benchmark::cmpthese( Benchmark::timethese( -5, $proxy_tests ) );
Benchmark::cmpthese( Benchmark::timethese( -5, $call_tests ) );
Benchmark::cmpthese( Benchmark::timethese( -5, $method_tests ) );

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    1 │ 15, 20, 36, 41, 46,  │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## │      │ 54, 59               │                                                                                                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
