package Pcore::Devel::Profiler;

use strict;
use warnings;
use utf8;
use v5.20.0;

open my $fh, '>:raw', 'profile.csv' or die;    ## no critic qw(InputOutput::RequireBriefOpen)
say {$fh} 'package,caller,RES before,RES after,RES diff,VSZ before,VSZ after';

our %PACKAGES;

*CORE::GLOBAL::require = sub {
    my $package = $_[0];

    return if ref \$package eq 'VSTRING' || $package =~ /\A[\d.]+\z/sm;

    my $caller = caller;

    my $monitor;
    my $mem_before;
    unless ( exists $PACKAGES{$package} ) {
        $PACKAGES{$package} = 1;
        $monitor            = 1;
        $mem_before         = _get_mem();
    }

    my $sub = eval qq[package $caller; sub { CORE::require( \$_[0] ) }];    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
    my $res = $sub->($package);

    if ($monitor) {
        my $mem_after = _get_mem();

        my $res_diff = $mem_after->{res} - $mem_before->{res};

        say {$fh} qq[$package,$caller,$mem_before->{res},$mem_after->{res},$res_diff,$mem_before->{vsz},$mem_after->{vsz}];
    }

    return $res;
};

sub _get_mem {
    my $mem = {};

    ( $mem->{vsz}, $mem->{res} ) = split /\s+/sm, `ps -o vsz,rss --no-heading -p $$`;

    return $mem;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 8                    │ ErrorHandling::RequireCarping - "die" used instead of "croak"                                                  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 1                    │ Modules::RequireVersionVar - No package-scoped "$VERSION" variable found                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 9, 36                │ InputOutput::RequireCheckedSyscalls - Return value of flagged function ignored - say                           │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
