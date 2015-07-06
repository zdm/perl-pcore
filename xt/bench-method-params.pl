#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Const::Fast;
use Benchmark;
use URI;

Const::Fast::const our $COUNT => -10;

my $tests = {
    shift       => sub { return t_shift( 'self',       aaa => 'value', bbb => 'value', ccc => 'value' ); },
    copy_splice => sub { return t_copy_splice( 'self', aaa => 'value', bbb => 'value', ccc => 'value' ); },
    copy_slice  => sub { return t_copy_slice( 'self',  aaa => 'value', bbb => 'value', ccc => 'value' ); },
    sign_splice => sub { return t_sign_splice( 'self', aaa => 'value', bbb => 'value', ccc => 'value' ); },
    sign_slice  => sub { return t_sign_slice( 'self',  aaa => 'value', bbb => 'value', ccc => 'value' ); },
};

Benchmark::cmpthese( Benchmark::timethese( $COUNT, $tests ) );

# RESULTS:
# splice faster then slice on 20%;
# signatures is slower by 10% then equivalent;

sub t_shift {
    my $self = shift;
    my %args = (
        aaa => 1,
        bbb => 2,
        @_,
    );

    return;
}

sub t_copy_splice {
    my ($self) = @_;
    my %args = (
        aaa => 1,
        bbb => 2,
        splice( @_, 1 ),
    );

    return;
}

sub t_copy_slice {
    my ($self) = @_;
    my %args = (
        aaa => 1,
        bbb => 2,
        @_[ 1 .. $#_ ],
    );

    return;
}

sub t_sign_splice ( $self, @ ) {
    my %args = (
        aaa => 'default',
        bbb => 'default',
        splice( @_, 1 ),
    );

    return;
}

sub t_sign_slice ( $self, @ ) {
    my %args = (
        aaa => 'default',
        bbb => 'default',
        @_[ 1 .. $#_ ],
    );

    return;
}

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
