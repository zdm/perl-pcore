package Pcore::Core::Dist::VCS;

use Pcore qw[-class];
use Pcore::Core::Dist::VCS::Upstream;

has root => ( is => 'ro', isa => Str, required => 1 );

has is_git => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );
has is_hg  => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

has upstream => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Core::Dist::VCS::Upstream'] ], init_arg => undef );

around new => sub ( $orig, $self, $root ) {
    if ( -d $root . '/.hg/' ) {
        require Pcore::Core::Dist::VCS::Hg;

        return Pcore::Core::Dist::VCS::Hg->new( { root => $root } );
    }
    elsif ( -d $root . '/.git/' ) {
        require Pcore::Core::Dist::VCS::Git;

        return Pcore::Core::Dist::VCS::Git->new( { root => $root } );
    }
    else {
        return;
    }
};

no Pcore;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 14, 19               │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Dist::VCS

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
