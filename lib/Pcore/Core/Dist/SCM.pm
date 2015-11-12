package Pcore::Core::Dist::SCM;

use Pcore qw[-class];
use Pcore::Core::Dist::SCM::Upstream;

has root => ( is => 'ro', isa => Str, required => 1 );

has is_git => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );
has is_hg  => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

has upstream => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Core::Dist::SCM::Upstream'] ], init_arg => undef );

around new => sub ( $orig, $self, $root ) {
    if ( -d $root . '/.hg/' ) {
        require Pcore::Core::Dist::SCM::Hg;

        return Pcore::Core::Dist::SCM::Hg->new( { root => $root } );
    }
    elsif ( -d $root . '/.git/' ) {
        require Pcore::Core::Dist::SCM::Git;

        return Pcore::Core::Dist::SCM::Git->new( { root => $root } );
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

Pcore::Core::Dist::SCM

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
