package Pcore::Core::Env;

use Pcore -class;
use Config;
use File::Spec qw[];    ## no critic qw[Modules::ProhibitEvilModules] needed to find system temp dir
use Cwd qw[];           ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::Dist;
use Pcore::Core::Env::Share;
use Fcntl qw[LOCK_EX SEEK_SET];

has is_par => ( is => 'lazy', isa => Bool, init_arg => undef );    # process run from PAR distribution
has _main_dist => ( is => 'lazy', isa => Maybe      [ InstanceOf ['Pcore::Dist'] ], init_arg => undef );    # main dist
has pcore      => ( is => 'ro',   isa => InstanceOf ['Pcore::Dist'],                init_arg => undef );    # pcore dist
has share      => ( is => 'ro',   isa => InstanceOf ['Pcore::Core::Env::Share'],    init_arg => undef );    # share object
has _dist_idx     => ( is => 'ro',   isa => HashRef, init_arg => undef );                                   # registered dists. index
has cli           => ( is => 'ro',   isa => HashRef, init_arg => undef );                                   # parsed CLI data
has user_cfg_path => ( is => 'lazy', isa => Str,     init_arg => undef );
has user_cfg      => ( is => 'lazy', isa => HashRef, init_arg => undef );                                   # $HOME/.pcore/pcore.ini config

has can_scan_deps => ( is => 'lazy', isa => Bool, init_arg => undef );

_normalize_inc();

# create $ENV object
$ENV = __PACKAGE__->new;                                                                                    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

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
        my $is_module_build_test = 0;    # $ENV->dist && exists $inc_index->{ $ENV->dist->root . 'blib/lib' } ? 1 : 0;

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
                    if ( !exists $inc_index->{qq[$dir/lib]} && -d qq[$dir/lib/] && Pcore::Dist->dir_is_dist_root($dir) ) {
                        $inc_index->{qq[$dir/lib]} = 1;

                        unshift @inc, qq[$dir/lib];
                    }
                }
            }

            # register dist lib path in @INC, dist lib path is always on top of other dists
            unshift @inc, $dist_lib_path if $dist_lib_path;
        }
    }

    @INC = @inc;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return;
}

sub BUILD ( $self, $args ) {

    # init share
    $self->{share} = Pcore::Core::Env::Share->new;

    $self->{START_DIR} = P->file->cwd->to_string;

    if ( $Pcore::SCRIPT_PATH eq '-e' || $Pcore::SCRIPT_PATH eq '-' ) {
        $self->{SCRIPT_NAME} = '-e';
        $self->{SCRIPT_DIR}  = $self->{START_DIR};
    }
    else {
        die qq[Cannot find current script "$Pcore::SCRIPT_PATH"] if !-f $Pcore::SCRIPT_PATH;

        my $path = P->path($Pcore::SCRIPT_PATH)->realpath;

        $self->{SCRIPT_NAME} = $path->filename;
        $self->{SCRIPT_DIR}  = $path->dirname;
    }

    $self->{SCRIPT_PATH} = $self->{SCRIPT_DIR} . $self->{SCRIPT_NAME};

    $self->{SYS_TEMP_DIR} = P->path( File::Spec->tmpdir, is_dir => 1 )->to_string;
    $self->{TEMP_DIR} = P->file->tempdir( base => $self->{SYS_TEMP_DIR}, lazy => 1 );
    $self->{USER_DIR} = P->path( $ENV{HOME} || $ENV{USERPROFILE}, is_dir => 1 );
    $self->{PCORE_USER_DIR} = P->path( $self->{USER_DIR} . '.pcore/',     is_dir => 1, lazy => 1 );
    $self->{PCORE_SYS_DIR}  = P->path( $self->{SYS_TEMP_DIR} . '.pcore/', is_dir => 1, lazy => 1 );
    $self->{INLINE_DIR} = $self->is_par ? undef : P->path( $self->{PCORE_USER_DIR} . "inline/$Config{version}/$Config{archname}/", is_dir => 1, lazy => 1 );

    # CLI options
    $self->{SCAN_DEPS} = 0;
    $self->{DAEMONIZE} = 0;
    $self->{UID}       = undef;
    $self->{GID}       = undef;

    # load dist cfg
    if ( my $dist = $self->dist ) {
        if ( $self->is_par ) {
            $self->{DATA_DIR} = $self->{SCRIPT_DIR};
        }
        else {
            $self->{DATA_DIR} = P->path( $dist->root . 'data/', is_dir => 1, lazy => 1 );
        }
    }
    else {
        $self->{DATA_DIR} = $self->{START_DIR};
    }

    # init pcore dist, needed to register pcore resources during bootstrap
    if ( $self->dist && $self->dist->is_pcore ) {
        $self->{pcore} = $self->dist;
    }
    else {
        $self->{pcore} = Pcore::Dist->new('Pcore.pm');

        $self->register_dist( $self->{pcore} );
    }

    return;
}

sub _build_is_par ($self) {
    return $ENV{PAR_TEMP} ? 1 : 0;
}

sub _build__main_dist ($self) {
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

sub _build_user_cfg_path ($self) {
    return "$self->{PCORE_USER_DIR}pcore.ini";
}

sub _build_user_cfg ($self) {
    if ( !-f $self->user_cfg_path ) {
        return {};
    }
    else {
        return P->cfg->load( $self->user_cfg_path );
    }
}

sub register_dist ( $self, $dist ) {

    # create dist object
    $dist = Pcore::Dist->new($dist) if !ref $dist;

    # dist was not found
    die qq[Invlaid Pcore -dist pragma usage, "$dist" is not a Pcore dist main module] if !$dist;

    # dist is already registered
    return if exists $self->{_dist_idx}->{ $dist->name };

    # add dist to the dists index
    $self->{_dist_idx}->{ $dist->name } = $dist;

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

    $self->{share}->add_lib( $dist->name, $dist->share_dir, $share_lib_level );

    return;
}

sub dist ( $self, $dist_name = undef ) {
    if ($dist_name) {
        return $self->{_dist_idx}->{ $dist_name =~ s/::/-/smgr };
    }
    else {
        return $self->_main_dist;
    }
}

# SCAN DEPS
sub _build_can_scan_deps ($self) {
    return !$self->is_par && $self->dist && $self->dist->par_cfg && exists $self->dist->par_cfg->{ $self->{SCRIPT_NAME} };
}

sub scan_deps ($self) {
    return if !$self->can_scan_deps;

    $self->{SCAN_DEPS} = $self->dist->share_dir . "pardeps-$self->{SCRIPT_NAME}-@{[$^V->normal]}-$Config{archname}.json";

    # eval TypeTiny Error
    eval { Int->('error') };

    # eval common modules
    require Cpanel::JSON::XS;    ## no critic qw[Modules::ProhibitEvilModules]

    return;
}

sub DEMOLISH ( $self, $global ) {
    if ( $self->{SCAN_DEPS} ) {
        my ( $fh, $index );

        if ( -f $self->{SCAN_DEPS} ) {
            open $fh, '+<:raw', $self->{SCAN_DEPS} or die;    ## no critic qw[InputOutput::RequireBriefOpen]

            flock $fh, LOCK_EX or die;

            local $/;

            my $deps = Cpanel::JSON::XS->new->utf8->decode(<$fh>);

            $index->@{ $deps->@* } = ();
        }
        else {
            open $fh, '>:raw', $self->{SCAN_DEPS} or die;     ## no critic qw[InputOutput::RequireBriefOpen]

            flock $fh, LOCK_EX or die;
        }

        my ( $updated, $embedded_packages );

        for my $module ( sort keys %INC ) {
            if ( !exists $index->{$module} ) {
                if ( $INC{$module} !~ /\Q$module\E\z/sm ) {
                    $embedded_packages->{$module} = $INC{$module};
                }
                else {
                    $updated = 1;

                    $index->{$module} = undef;

                    say qq[new deps found: $module];
                }
            }
        }

        # find real module for embedded modules
        if ($embedded_packages) {
            for my $embedded_package ( keys $embedded_packages->%* ) {
                my $added;

                for my $module ( keys %INC ) {
                    if ( $INC{$module} eq $embedded_packages->{$embedded_package} ) {

                        # embedded package is already added
                        if ( exists $index->{$module} ) {

                            # say "$module ---> $embedded_package";

                            $added = 1;

                            last;
                        }
                    }
                }

                if ( !$added ) {
                    $updated = 1;

                    $index->{$embedded_package} = undef;

                    say qq[new deps found: $embedded_package];
                }
            }
        }

        # store deps
        if ($updated) {
            truncate $fh, 0 or die;

            seek $fh, 0, SEEK_SET or die;

            print {$fh} Cpanel::JSON::XS->new->utf8->canonical->pretty->encode( [ sort keys $index->%* ] );
        }

        close $fh or die;
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
## |    3 | 270                  | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 278                  | Subroutines::ProhibitExcessComplexity - Subroutine "DEMOLISH" with high complexity score (22)                  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 287                  | Variables::RequireInitializationForLocalVars - "local" variable not initialized                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 325                  | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 352                  | ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 5                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 99                   | BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
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
