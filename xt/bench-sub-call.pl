#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Benchmark;

my @args = ( 1, 2, 3 );

sub sub1 {
    return;
}

sub sub2 {
    &sub1;    ## no critic qw[Subroutines::ProhibitAmpersandSigils]

    return;
}

sub sub3 {
    sub1(@_);

    return;
}

sub sub4 {
    sub1 @_;

    return;
}

sub goto1 {
    goto &sub1;
}

my $goto_tests = {
    'goto()' => sub {
        goto1();

        return;
    },
    'goto(@_)' => sub {
        goto1(1);

        return;
    },
    'sub()' => sub {
        sub2();

        return;
    },
    'sub(@_)' => sub {
        sub2(1);

        return;
    },
};

my $proxy_tests = {
    'sub(@_)' => sub {    # static function, new stack
        sub3(1);

        return;
    },
    'sub @_' => sub {     # static function, new stack, checked at compile time
        sub4(1);

        return;
    },
    '&sub(@_)' => sub {    # static function, reuse stack
        sub2(1);

        return;
    },
    '&sub()' => sub {      # static function, reuse stack
        sub2();

        return;
    },
    'goto (@_)' => sub {
        goto1(1);

        return;
    },
    'goto ()' => sub {
        goto1();

        return;
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

Benchmark::cmpthese( Benchmark::timethese( -5, $goto_tests ) );
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
## │    1 │ 42, 52, 60, 65, 70,  │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## │      │ 80, 93, 98, 103,     │                                                                                                                │
## │      │ 111, 116             │                                                                                                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
