package Pcore::Core::Env;

use Pcore -class;
use Config;
use File::Spec qw[];    ## no critic qw[Modules::ProhibitEvilModules] needed to find system temp dir
use Pcore::Dist;
use Pcore::Core::Env::Share;

has is_par => ( is => 'lazy', isa => Bool, init_arg => undef );
has dist => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Dist'] ], init_arg => undef );    # main dist
has pcore => ( is => 'lazy', isa => InstanceOf ['Pcore::Dist'],             init_arg => undef ); # pcore dist
has share => ( is => 'lazy', isa => InstanceOf ['Pcore::Core::Env::Share'], init_arg => undef ); # share object
has dist_idx => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );      # registered dists. index

# TODO remove CFG
sub CORE_INIT ($self) {
    $self->{START_DIR}      = P->file->cwd->to_string;
    $self->{SCRIPT_NAME}    = $FindBin::RealScript;
    $self->{SCRIPT_DIR}     = P->path( $FindBin::RealBin, is_dir => 1 )->realpath->to_string;
    $self->{SCRIPT_PATH}    = $self->{SCRIPT_DIR} . $self->{SCRIPT_NAME};
    $self->{SYS_TEMP_DIR}   = P->path( File::Spec->tmpdir, is_dir => 1 )->to_string;
    $self->{TEMP_DIR}       = P->file->tempdir( base => $self->{SYS_TEMP_DIR}, lazy => 1 );
    $self->{USER_DIR}       = P->path( $ENV{HOME} || $ENV{USERPROFILE}, is_dir => 1 );
    $self->{PCORE_USER_DIR} = P->path( $self->{USER_DIR} . '.pcore/', is_dir => 1, lazy => 1 );
    $self->{PCORE_SYS_DIR}  = P->path( $self->{SYS_TEMP_DIR} . '.pcore/', is_dir => 1, lazy => 1 );
    $self->{INLINE_DIR}     = $self->is_par ? undef : P->path( $self->{PCORE_USER_DIR} . "inline/$Config{version}/$Config{archname}/", is_dir => 1, lazy => 1 );

    # load dist.perl
    if ( my $dist = $self->dist ) {

        # TODO - do not merge with dist cfg, just store as CFG
        $self->{CFG} = $dist->cfg;

        if ( $self->is_par ) {
            $self->{DATA_DIR} = undef;
            $self->{LOG_DIR} = P->path( $ENV{PAR_TEMP} . '/log/', is_dir => 1, lazy => 1 );
        }
        else {
            $self->{DATA_DIR} = P->path( $dist->root . 'data/', is_dir => 1, lazy => 1 );
            $self->{LOG_DIR}  = P->path( $dist->root . 'log/',  is_dir => 1, lazy => 1 );
        }
    }
    else {
        $self->{CFG} = {};

        $self->{DATA_DIR} = undef;
        $self->{LOG_DIR}  = undef;
    }

    # init pcore dist, needed to register pcore resources during bootstrap
    $self->pcore;

    return;
}

sub _build_is_par ($self) {
    return $ENV{PAR_TEMP} ? 1 : 0;
}

sub _build_dist ($self) {
    my $dist;

    if ( $self->is_par ) {
        $dist = Pcore::Dist->new( $ENV{PAR_TEMP} );
    }
    else {
        $dist = Pcore::Dist->new( $self->{SCRIPT_DIR} );
    }

    if ($dist) {
        $dist->{is_main} = 1;

        $self->register_dist($dist);
    }

    return $dist;
}

sub _build_pcore ($self) {
    if ( $self->dist && $self->dist->is_pcore ) {
        return $self->dist;
    }
    else {
        my $pcore = Pcore::Dist->new('Pcore.pm');

        $self->register_dist($pcore);

        return $pcore;
    }
}

sub _build_share ($self) {
    return Pcore::Core::Env::Share->new;
}

sub register_dist ( $self, $dist ) {

    # create dist object
    $dist = Pcore::Dist->new($dist) if !ref $dist;

    # dist was not found
    die qq[Invlaid Pcore -dist pragma usage, "$dist" is not a Pcore dist main module] if !$dist;

    # dist is already registered
    return if exists $self->dist_idx->{ lc $dist->name };

    # add dist to the dists index
    $self->dist_idx->{ lc $dist->name } = $dist;

    # register dist utils
    if ( $dist->cfg->{util} ) {
        for my $util ( keys $dist->cfg->{util}->%* ) {
            die qq[Pcore util "$util" is already registered] if exists $Pcore::UTIL->{$util};

            $Pcore::UTIL->{$util} = $dist->cfg->{util}->{$util};
        }
    }

    # register dist share
    my $share_lib_level;

    if ( $dist->is_pcore ) {    # pcore dist is always first
        $share_lib_level = 0;
    }
    elsif ( $dist->is_main ) {    # main dist is always on top
        $share_lib_level = 9_999;

    }
    else {
        state $next_level = 10;

        $share_lib_level = $next_level++;
    }

    $self->share->add_lib( lc $dist->name, $dist->share_dir, $share_lib_level );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 112                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Env

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
