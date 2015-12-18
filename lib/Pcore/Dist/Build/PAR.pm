package Pcore::Dist::Build::PAR;

use Pcore -class;
use Config qw[];
use Pcore::Dist::Build::PAR::Script;
use Term::ANSIColor qw[:constants];

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has release => ( is => 'ro', isa => Bool, default => 0 );
has crypt => ( is => 'ro', isa => Maybe [Bool] );
has upx   => ( is => 'ro', isa => Maybe [Bool] );
has clean => ( is => 'ro', isa => Maybe [Bool] );

no Pcore;

sub run ($self) {

    # load .pardeps.cbor
    my $pardeps;

    if ( -f $self->dist->root . 'data/.pardeps.cbor' ) {
        $pardeps = P->cfg->load( $self->dist->root . 'data/.pardeps.cbor' );
    }
    else {
        say q["data/.pardeps.cbor" is not exists.];

        say q[Run source scripts with --scan-deps option.];

        exit 1;
    }

    # check for distribution has configure PAR profiles in dist.perl
    if ( !$self->dist->cfg->{dist}->{par} && !ref $self->dist->cfg->{dist}->{par} eq 'HASH' ) {
        say q[par profile wasn't found.];

        exit 1;
    }

    # load global pcore.perl config
    my $pcore_cfg = P->cfg->load( $ENV->res->get( '/data/pcore.perl', lib => 'pcore' ) );

    # build scripts
    for my $script ( sort keys $self->dist->cfg->{dist}->{par}->%* ) {
        my $profile = $self->dist->cfg->{dist}->{par}->{$script};

        $profile->{dist} = $self->dist;

        $profile->{par_deps} = $pcore_cfg->{par_deps} // [];

        $profile->{arch_deps} = $pcore_cfg->{arch_deps}->{ $Config::Config{archname} } // {};

        $profile->{script} = P->path( $self->dist->root . 'bin/' . $script );

        $profile->{release} = $self->release;

        $profile->{crypt} = $self->crypt if defined $self->crypt;

        $profile->{upx} = $self->upx if defined $self->upx;

        $profile->{clean} = $self->clean if defined $self->clean;

        if ( !exists $pardeps->{$script}->{ $Config::Config{archname} } ) {
            say BOLD . RED . qq[Deps for $script "$Config::Config{archname}" wasn't scanned.] . RESET;

            say qq[Run "$script ---scan-deps"];

            next;
        }
        else {
            $profile->{script_deps} = $pardeps->{$script}->{ $Config::Config{archname} };
        }

        Pcore::Dist::Build::PAR::Script->new($profile)->run;
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 44                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::PAR - build PAR executable

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
