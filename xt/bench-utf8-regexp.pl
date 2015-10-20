#!/usr/bin/env perl

package main v0.1.0;

use Pcore qw[-const];
use Benchmark qw[];

const our $COUNT => -3;

# benchmark regex operations with upgraded / downgraded UTF-8 scalar

my $scalar_upgraded = q[abc£££££] x ( 1024 * 256 );

my $scalar_downgraded = $scalar_upgraded;

utf8::downgrade($scalar_downgraded);

say q[Bench regex speed for different scalar types: upgraded, downgraded];

say q[Upgraded length: ] . bytes::length($scalar_upgraded);

say q[Downgraded length: ] . bytes::length($scalar_downgraded);

my $res = Benchmark::timethese(
    $COUNT,
    {   'UTF-8 upgraded' => sub {
            $scalar_upgraded =~ s/c£//smg;
            return;
        },
        'UTF-8 downgraded' => sub {
            $scalar_downgraded =~ s/c£//smg;
            return;
        },
        'UTF-8 down - up grade' => sub {
            utf8::downgrade($scalar_upgraded);
            $scalar_upgraded =~ s/c£//smg;
            utf8::upgrade($scalar_upgraded);
            return;
        },
    }
);

Benchmark::cmpthese($res);

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
