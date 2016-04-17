package Pcore::Dist::Build::PAR;

use Pcore -class, -ansi;
use Config;
use Pcore::Dist::Build::PAR::Script;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has crypt => ( is => 'ro', isa => Maybe [Bool] );
has upx   => ( is => 'ro', isa => Maybe [Bool] );
has clean => ( is => 'ro', isa => Maybe [Bool] );

has release => ( is => 'lazy', isa => Bool, init_arg => undef );

sub _build_release ($self) {
    if ( $self->dist->id->{current_release} && !$self->dist->id->{current_release_distance} ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub run ($self) {
    if ( !$self->dist->scm ) {
        say q[SCM is required];

        exit 1;
    }
    elsif ( !$self->dist->is_commited ) {
        say q[Working copy has uncommited changes];

        exit 1;
    }

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
    if ( !$self->dist->cfg->{par} && !ref $self->dist->cfg->{par} eq 'HASH' ) {
        say q[par profile wasn't found.];

        exit 1;
    }

    # load global pcore.perl config
    my $pcore_cfg = P->cfg->load( $ENV->share->get( '/data/pcore.perl', lib => 'Pcore' ) );

    # build scripts
    for my $script ( sort keys $self->dist->cfg->{par}->%* ) {
        if ( !exists $pardeps->{$script}->{ $Config{archname} } ) {
            say BOLD . RED . qq[Deps for $script "$Config{archname}" wasn't scanned.] . RESET;

            say qq[Run "$script ---scan-deps"];

            next;
        }

        my $profile = $self->dist->cfg->{par}->{$script};

        $profile->{dist}    = $self->dist;
        $profile->{script}  = P->path( $self->dist->root . 'bin/' . $script );
        $profile->{release} = $self->release;
        $profile->{crypt}   = $self->crypt if defined $self->crypt;
        $profile->{upx}     = $self->upx if defined $self->upx;
        $profile->{clean}   = $self->clean if defined $self->clean;

        # add pardeps.cbor modules, skip eval records
        $profile->{mod}->@{ grep { !/\A[(]eval\s/sm } keys $pardeps->{$script}->{ $Config{archname} }->%* } = ();

        # add global modules
        $profile->{mod}->@{ $pcore_cfg->{par}->{mod}->@* } = ();

        # add global arch modules
        $profile->{mod}->@{ $pcore_cfg->{par}->{arch}->{ $Config{archname} }->{mod}->@* } = () if exists $pcore_cfg->{par}->{arch}->{ $Config{archname} }->{mod};

        # replace Inline.pm with Pcore/Core/Inline.pm
        $profile->{mod}->{'Pcore/Core/Inline.pm'} = undef if delete $profile->{mod}->{'Inline.pm'};

        # add Filter::Crypto::Decrypt deps if crypt mode is used
        $profile->{mod}->{'Filter/Crypto/Decrypt.pm'} = undef if $profile->{crypt};

        # index and add script shares
        my $share = {};

        $share->@{ $profile->{share}->@* } = () if $profile->{share};

        $profile->{share} = $share;

        # index and add shlib
        my $shlib = {};

        if ( exists $pcore_cfg->{par}->{arch}->{ $Config{archname} }->{mod_shlib} ) {
            for my $mod ( grep { exists $profile->{mod}->{$_} } keys $pcore_cfg->{par}->{arch}->{ $Config{archname} }->{mod_shlib}->%* ) {
                $shlib->@{ $pcore_cfg->{par}->{arch}->{ $Config{archname} }->{mod_shlib}->{$mod}->@* } = ();
            }
        }

        $profile->{shlib} = [ keys $shlib->%* ];

        Pcore::Dist::Build::PAR::Script->new($profile)->run;
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 61, 80, 105, 110     | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
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
