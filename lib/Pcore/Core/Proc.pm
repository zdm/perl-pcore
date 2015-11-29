package Pcore::Core::Proc;

use Pcore qw[-class];
use Config qw[];
use File::Spec qw[];    ## no critic qw[Modules::ProhibitEvilModules] needed to find system temp dir
use Pcore::Dist;
use Pcore::Core::Proc::Res;

has is_par => ( is => 'lazy', isa => Bool, init_arg => undef );
has dist => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Dist'] ], init_arg => undef );
has pcore => ( is => 'lazy', isa => InstanceOf ['Pcore::Dist'],            init_arg => undef );
has res   => ( is => 'lazy', isa => InstanceOf ['Pcore::Core::Proc::Res'], init_arg => undef );

has cfg => ( is => 'ro', isa => HashRef, init_arg => undef );

no Pcore;

sub BUILD ( $self, $args ) {
    $self->{START_DIR}    = P->file->cwd->to_string;
    $self->{SCRIPT_NAME}  = $FindBin::RealScript;
    $self->{SCRIPT_DIR}   = P->path( $FindBin::RealBin, is_dir => 1 )->realpath->to_string;
    $self->{SCRIPT_PATH}  = $self->{SCRIPT_DIR} . $self->{SCRIPT_NAME};
    $self->{SYS_TEMP_DIR} = P->path( File::Spec->tmpdir, is_dir => 1 )->to_string;
    $self->{TEMP_DIR}     = P->file->tempdir( base => $self->{SYS_TEMP_DIR}, lazy => 1 );

    # load dist.perl
    if ( my $dist = $self->dist ) {
        $self->{cfg} = $args ? P->hash->merge( $dist->cfg, $args ) : $dist->cfg;

        if ( $dist->is_par ) {
            $self->{DATA_DIR} = undef;
            $self->{LOG_DIR} = P->path( $ENV{PAR_TEMP} . '/log/', is_dir => 1, lazy => 1 );
        }
        else {
            $self->{DATA_DIR} = P->path( $dist->root . 'data/', is_dir => 1, lazy => 1 );
            $self->{LOG_DIR}  = P->path( $dist->root . 'log/',  is_dir => 1, lazy => 1 );
        }
    }
    else {
        $self->{cfg} = $args // {};

        $self->{DATA_DIR} = undef;
        $self->{LOG_DIR}  = undef;
    }

    # conligure inline dir
    if ( $self->dist && $self->dist->is_par ) {
        $self->{INLINE_DIR} = P->path( $ENV{PAR_TEMP} . '/inc/' . $Config::Config{version} . q[/] . $Config::Config{archname} . q[/], is_dir => 1, lazy => 1 );
    }
    else {
        if ( $self->pcore->is_installed ) {
            $self->{INLINE_DIR} = P->path( $self->pcore->share_dir . '.inline/', is_dir => 1, lazy => 1 );
        }
        else {
            $self->{INLINE_DIR} = P->path( $self->pcore->root . '.inline/' . $Config::Config{version} . q[/] . $Config::Config{archname} . q[/], is_dir => 1, lazy => 1 );
        }
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
    if ( $self->dist && $self->dist->name eq 'Pcore' ) {
        return $self->dist;
    }
    else {
        return Pcore::Dist->new('Pcore.pm');
    }
}

# TODO
# new ENV - PCORE_RESOURCES - PCORE_RES_LIB
sub _build_res ($self) {
    my $res = Pcore::Core::Proc::Res->new;

    $res->add_lib( 'pcore', $self->pcore->share_dir );

    $res->add_lib( 'dist', $self->dist->share_dir ) if $self->dist;

    # TODO how to get priority
    if ( $ENV{PCORE_RESOURCES} && -d $ENV{PCORE_RESOURCES} ) {
        opendir my $dh, $ENV{PCORE_RESOURCES} || die;

        while ( my $dir = readdir $dh ) {
            next if $dir eq q[.] or $dir eq q[..];

            my $lib_dir = $ENV{PCORE_RESOURCES} . q[/] . $dir;

            $res->add_lib( $dir, P->path( $lib_dir, is_dir => 1 )->to_string ) if -d $lib_dir;
        }

        closedir $dh or die;
    }

    return $res;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Proc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
