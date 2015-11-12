package Pcore::Src::SCM;

use Pcore qw[-class];
use Pcore::Src::SCM::Upstream;

has root => ( is => 'ro', isa => Str, required => 1 );

has is_git => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );
has is_hg  => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

has upstream => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Src::SCM::Upstream'] ], init_arg => undef );
has server => ( is => 'lazy', isa => Object, clearer => 1, init_arg => undef );

around new => sub ( $orig, $self, $path ) {
    $path = P->path( $path, is_dir => 1 ) if !ref $path;

    my $scm;

    if ( -d $path . '/.git/' ) {
        $scm = 'Git';
    }
    elsif ( -d $path . '/.hg/' ) {
        $scm = 'Hg';
    }
    else {
        $path = $path->parent;

        while ($path) {
            if ( -d $path . '/.git/' ) {
                $scm = 'Git';

                last;
            }
            elsif ( -d $path . '/.hg/' ) {
                $scm = 'Hg';

                last;
            }

            $path = $path->parent;
        }
    }

    if ($scm) {
        return P->class->load( $scm, ns => 'Pcore::Src::SCM' )->new( { root => $path->to_string } );
    }
    else {
        return;
    }
};

sub _build_server ($self) {
    return P->class->load( 'Server', ns => ref $self )->new( { root => $self->root } );
}

no Pcore;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 19, 22, 29, 34       │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src::SCM

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
