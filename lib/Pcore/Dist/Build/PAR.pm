package Pcore::Dist::Build::PAR;

use Pcore -class;
use Config;
use Pcore::Dist::Build::PAR::Script;
use Term::ANSIColor qw[:constants];

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has release => ( is => 'ro', isa => Bool, default => 0 );
has crypt => ( is => 'ro', isa => Maybe [Bool] );
has upx   => ( is => 'ro', isa => Maybe [Bool] );
has clean => ( is => 'ro', isa => Maybe [Bool] );

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
    my $pcore_cfg = P->cfg->load( $ENV->share->get( '/data/pcore.perl', lib => 'pcore' ) );

    # build scripts
    for my $script ( sort keys $self->dist->cfg->{dist}->{par}->%* ) {
        if ( !exists $pardeps->{$script}->{ $Config{archname} } ) {
            say BOLD . RED . qq[Deps for $script "$Config{archname}" wasn't scanned.] . RESET;

            say qq[Run "$script ---scan-deps"];

            next;
        }

        my $profile = $self->dist->cfg->{dist}->{par}->{$script};

        $profile->{dist}    = $self->dist;
        $profile->{script}  = P->path( $self->dist->root . 'bin/' . $script );
        $profile->{release} = $self->release;
        $profile->{crypt}   = $self->crypt if defined $self->crypt;
        $profile->{upx}     = $self->upx if defined $self->upx;
        $profile->{clean}   = $self->clean if defined $self->clean;

        # add pardeps.cbor modules, skip eval
        $profile->{mod}->@{ grep { !/\A[(]eval\s/sm } keys $pardeps->{$script}->{ $Config{archname} }->%* } = ();

        # add global modules
        $profile->{mod}->@{ $pcore_cfg->{par}->{mod}->@* } = ();

        # add global arch modules
        $profile->{mod}->@{ $pcore_cfg->{par}->{arch}->{ $Config{archname} }->{mod}->@* } = () if exists $pcore_cfg->{par}->{arch}->{ $Config{archname} }->{mod};

        # replace Inline.pm with Pcore/Core/Inline.pm
        $profile->{mod}->{'Pcore/Core/Inline.pm'} = undef if delete $profile->{mod}->{'Inline.pm'};

        # add Filter::Crypto::Decrypt deps if crypt mode is used
        $profile->{mod}->{'Filter/Crypto/Decrypt.pm'} = undef if $profile->{crypt};

        my $share = {};

        # add script shares
        $share->@{ $profile->{share}->@* } = () if $profile->{share};

        # add shares, required by used modules
        for my $mod ( grep { exists $profile->{mod}->{$_} } keys $pcore_cfg->{par}->{mod_share}->%* ) {
            $share->@{ $pcore_cfg->{par}->{mod_share}->{$mod}->@* } = ();
        }

        $profile->{resource} = [ keys $share->%* ];

        # add shlib
        my $shlib = {};

        if ( exists $pcore_cfg->{par}->{arch}->{ $Config{archname} }->{mod_shlib} ) {
            for my $mod ( grep { exists $profile->{mod}->{$_} } keys $pcore_cfg->{par}->{arch}->{ $Config{archname} }->{mod_shlib}->%* ) {
                $shlib->@{ $pcore_cfg->{par}->{arch}->{ $Config{archname} }->{mod_shlib}->{$mod}->@* } = ();
            }
        }

        $profile->{shlib} = [ keys $shlib->%* ];

        $profile->{mod} = [ keys $profile->{mod}->%* ];

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
## │    3 │ 42, 61, 81, 85, 91,  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 96, 98               │                                                                                                                │
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
