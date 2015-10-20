#!/usr/bin/env perl

package main v0.1.0;

use Pcore qw[-const];
use Benchmark qw[];

const our $COUNT => -5;

package _Bench::Moo::Accessors {

    use Pcore qw[-class];

    has ro            => ( is => 'ro' );
    has ro_isa        => ( is => 'ro', isa => Bool );
    has rw            => ( is => 'rw' );
    has rw_isa        => ( is => 'rw', isa => Bool );
    has rwp           => ( is => 'rwp' );
    has rwp_isa       => ( is => 'rwp', isa => Bool );
    has ro_writer     => ( is => 'ro', writer => 'set_ro_writer' );
    has ro_writer_isa => ( is => 'ro', isa => Bool, writer => 'set_ro_writer_isa' );

    no Pcore;
}

my $obj = _Bench::Moo::Accessors->new;

my $tests;

for my $attr ( keys P->moo->get_attrs($obj) ) {
    $tests->{$attr} = sub {
        $obj->$attr;

        return;
    };
}

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
