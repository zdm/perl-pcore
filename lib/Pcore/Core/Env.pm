package Pcore::Core::Env;

use Pcore -class;
use Config qw[];
use File::Spec qw[];    ## no critic qw[Modules::ProhibitEvilModules] needed to find system temp dir
use Pcore::Dist;
use Pcore::Core::Env::Resources;

has is_par => ( is => 'lazy', isa => Bool, init_arg => undef );
has dist => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Dist'] ], init_arg => undef );
has pcore => ( is => 'lazy', isa => InstanceOf ['Pcore::Dist'], init_arg => undef );
has res => ( is => 'lazy', isa => InstanceOf ['Pcore::Core::Env::Resources'], init_arg => undef );

no Pcore;

sub BUILD ( $self, $args ) {
    $self->{START_DIR}      = P->file->cwd->to_string;
    $self->{SCRIPT_NAME}    = $FindBin::RealScript;
    $self->{SCRIPT_DIR}     = P->path( $FindBin::RealBin, is_dir => 1 )->realpath->to_string;
    $self->{SCRIPT_PATH}    = $self->{SCRIPT_DIR} . $self->{SCRIPT_NAME};
    $self->{SYS_TEMP_DIR}   = P->path( File::Spec->tmpdir, is_dir => 1 )->to_string;
    $self->{TEMP_DIR}       = P->file->tempdir( base => $self->{SYS_TEMP_DIR}, lazy => 1 );
    $self->{USER_DIR}       = P->path( $ENV{HOME} || $ENV{USERPROFILE}, is_dir => 1 );
    $self->{PCORE_USER_DIR} = P->path( $self->{USER_DIR} . '.pcore/', is_dir => 1, lazy => 1 );
    $self->{PCORE_SYS_DIR}  = P->path( $self->{SYS_TEMP_DIR} . '.pcore/', is_dir => 1, lazy => 1 );
    $self->{INLINE_DIR}     = $self->is_par ? undef : P->path( $self->{PCORE_USER_DIR} . "inline/$Config::Config{version}/$Config::Config{archname}/", is_dir => 1, lazy => 1 );

    # load dist.perl
    if ( my $dist = $self->dist ) {
        $self->{CFG} = $args ? P->hash->merge( $dist->cfg, $args ) : $dist->cfg;

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
        $self->{CFG} = $args // {};

        $self->{DATA_DIR} = undef;
        $self->{LOG_DIR}  = undef;
    }

    return;
}

sub _build_is_par ($self) {
    return $ENV{PAR_TEMP} ? 1 : 0;
}

sub _build_dist ($self) {
    if ( $self->is_par ) {
        return Pcore::Dist->new( $ENV{PAR_TEMP} );
    }
    else {
        return Pcore::Dist->new( $self->{SCRIPT_DIR} );
    }
}

sub _build_pcore ($self) {
    my $pcore = Pcore::Dist->new('Pcore.pm');

    if ( $self->dist && $self->dist->module->path eq $pcore->module->path ) {
        return $self->dist;
    }
    else {
        return $pcore;
    }
}

# TODO priority
sub _build_res ($self) {
    my $res = Pcore::Core::Env::Resources->new;

    if ( $self->is_par ) {

        # under PAR pcore resources are merged with dist resources
        $res->_add_lib( 'pcore', $self->dist->share_dir ) if $self->dist;
    }
    else {
        $res->_add_lib( 'pcore', $self->pcore->share_dir );
    }

    $res->_add_lib( 'dist', $self->dist->share_dir ) if $self->dist;

    # TODO how to get priority
    if ( $ENV{PCORE_RES_LIB} && -d $ENV{PCORE_RES_LIB} ) {
        my $base_path = P->path( $ENV{PCORE_RES_LIB}, is_dir => 1 );

        for my $path ( P->file->read_dir( $base_path, full_path => 0 )->@* ) {
            my $lib_dir = $base_path . $path;

            $res->add_lib( $path, $lib_dir ) if -d $lib_dir;
        }
    }

    return $res;
}

1;
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
