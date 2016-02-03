package Pcore::Core::Env;

use Pcore -class;
use Config;
use File::Spec qw[];    ## no critic qw[Modules::ProhibitEvilModules] needed to find system temp dir
use Cwd qw[];           ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::Dist;
use Pcore::Core::Env::Share;

has is_par => ( is => 'lazy', isa => Bool, init_arg => undef );
has dist => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Dist'] ], init_arg => undef );    # main dist
has pcore => ( is => 'lazy', isa => InstanceOf ['Pcore::Dist'],             init_arg => undef ); # pcore dist
has share => ( is => 'lazy', isa => InstanceOf ['Pcore::Core::Env::Share'], init_arg => undef ); # share object
has dist_idx => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );      # registered dists. index
has cli      => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );      # parsed CLI data

# may not work, if executed in one-liner script
eval { require FindBin; };

if ($@) {
    $FindBin::Bin = $FindBin::RealBin = Cwd::getcwd();

    $FindBin::Script = $FindBin::RealScript = $0 =~ s[\A.*?[/\\](.+)\z][$1]smr;

    # prevent attempts to reload FindBin later
    delete $INC{'FindBin.pm'};

    $INC{'FindBin.pm'} = 'eval()';    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
}

_normalize_inc();

# create $ENV object
$ENV = __PACKAGE__->new;              ## no critic qw[Variables::RequireLocalizedPunctuationVars]

$ENV->_INIT;

_configure_inc();

sub _normalize_inc {
    my @inc;

    my $inc_index;

    # index @INC, resolve @INC paths, remove duplicates, preserve REF items
    for my $inc_path (@INC) {
        if ( ref $inc_path ) {
            push @inc, $inc_path;

            next;
        }

        # ignore relative script path, added by perl automatically
        next if $inc_path eq q[.];

        # ignore non-exists path
        next if !-d $inc_path;

        $inc_path = P->path( $inc_path, is_dir => 1 )->realpath->canonpath;

        # ignore already added path
        if ( !exists $inc_index->{$inc_path} ) {
            $inc_index->{$inc_path} = 1;

            push @inc, $inc_path;
        }
    }

    @INC = @inc;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return;
}

sub _configure_inc {
    my @inc;

    my $inc_index;

    # index @INC, resolve @INC paths, remove duplicates, preserve REF items
    for my $inc_path (@INC) {
        if ( ref $inc_path ) {
            push @inc, $inc_path;

            next;
        }

        # ignore already added path
        if ( !exists $inc_index->{$inc_path} ) {
            $inc_index->{$inc_path} = 1;

            push @inc, $inc_path;
        }
    }

    # not for PAR
    if ( !$ENV->is_par ) {
        my $is_module_build_test = $ENV->dist && exists $inc_index->{ $ENV->dist->root . 'blib/lib' } ? 1 : 0;

        # add dist lib and PCORE_LIB to @INC only if we are int on the PAR archive and not in the Module::Build testing environment
        # under Module::Build dist lib is already added and PCORE_LIB is not added to emulate clean CPAN installation
        if ( !$is_module_build_test ) {
            my $dist_lib_path;

            # detect dist lib path
            if ( $ENV->dist && !exists $inc_index->{ $ENV->dist->root . 'lib' } && -d $ENV->dist->root . 'lib/' ) {
                $dist_lib_path = $ENV->dist->root . 'lib';

                $inc_index->{$dist_lib_path} = 1;
            }

            # find and add other dist libs to @INC
            if ( $ENV{PCORE_LIB} && -d $ENV{PCORE_LIB} ) {
                for my $dir ( sort { $b cmp $a } P->file->read_dir( $ENV{PCORE_LIB}, full_path => 1 )->@* ) {
                    if ( !exists $inc_index->{qq[$dir/lib]} && -d qq[$dir/lib/] && Pcore::Dist->dir_is_dist($dir) ) {
                        $inc_index->{qq[$dir/lib]} = 1;

                        unshift @inc, qq[$dir/lib];
                    }
                }
            }

            # register dist lib path in @INC, dist lib path is always on top of other dists
            unshift @inc, $dist_lib_path if $dist_lib_path;
        }

        # add absolute script path, only if not in PAR mode
        my $script_path = P->path( $ENV->{SCRIPT_DIR}, is_dir => 1 )->canonpath;

        if ( !exists $inc_index->{$script_path} ) {
            $inc_index->{$script_path} = 1;

            push @inc, $script_path;
        }
    }

    @INC = @inc;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return;
}

sub _INIT ($self) {
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
    return if exists $self->dist_idx->{ $dist->name };

    # add dist to the dists index
    $self->dist_idx->{ $dist->name } = $dist;

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

    $self->share->add_lib( $dist->name, $dist->share_dir, $share_lib_level );

    return;
}

sub get_dist ( $self, $dist ) {
    return $self->dist_idx->{ $dist =~ s/::/-/smgr };
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 18                   │ ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 231                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 113                  │ BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                │
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
