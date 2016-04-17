#!/usr/bin/env perl

package main v0.1.0;

use Pcore -const;
use Benchmark qw[];

const our $COUNT => -5;

package _Bench::Moo::Accessors {

    use Pcore -class;

    has ro            => ( is => 'ro' );
    has ro_isa        => ( is => 'ro', isa => Bool );
    has rw            => ( is => 'rw' );
    has rw_isa        => ( is => 'rw', isa => Bool );
    has rwp           => ( is => 'rwp' );
    has rwp_isa       => ( is => 'rwp', isa => Bool );
    has ro_writer     => ( is => 'ro', writer => 'set_ro_writer' );
    has ro_writer_isa => ( is => 'ro', isa => Bool, writer => 'set_ro_writer_isa' );
}

my $obj = _Bench::Moo::Accessors->new;

my $tests;

for my $attr ( keys P->perl->moo->get_attrs($obj)->%* ) {
    $tests->{$attr} = sub {
        $obj->$attr;

        return;
    };
}

Benchmark::cmpthese( Benchmark::timethese( $COUNT, $tests ) );

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 28                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 28                   | ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
