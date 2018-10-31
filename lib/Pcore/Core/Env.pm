package Pcore::Core::Env;

use Pcore -class;
use Config;
use File::Spec qw[];    ## no critic qw[Modules::ProhibitEvilModules] needed to find system temp dir
use Cwd qw[];           ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::Dist;
use Pcore::Core::Env::Share;
use Fcntl qw[LOCK_EX SEEK_SET];
use Pcore::Util::Scalar qw[is_ref];

has is_par => ( is => 'ro', isa => Bool, init_arg => undef );    # process run from PAR distribution
has main_dist => ( is => 'ro', isa => Maybe      [ InstanceOf ['Pcore::Dist'] ], init_arg => undef );    # main dist
has pcore     => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'],                init_arg => undef );    # pcore dist
has share     => ( is => 'ro', isa => InstanceOf ['Pcore::Core::Env::Share'],    init_arg => undef );    # share object
has _dist_idx     => ( is => 'ro',   isa => HashRef, init_arg => undef );                                # registered dists. index
has cli           => ( is => 'ro',   isa => HashRef, init_arg => undef );                                # parsed CLI data
has user_cfg_path => ( is => 'lazy', isa => Str,     init_arg => undef );
has user_cfg      => ( is => 'lazy', isa => HashRef, init_arg => undef );                                # $HOME/.pcore/pcore.ini config

has PCORE_SHARE_DIR => ();
has SYS_USER_DIR    => ();                                                                               # OS user profile dir
has PCORE_USER_DIR  => ();                                                                               # SYS_USER_DIR/.pcore, pcore profile dir
has INLINE_DIR      => ();
has START_DIR       => ();
has SCRIPT_DIR      => ();
has SCRIPT_NAME     => ();
has SYS_TEMP_DIR    => ();                                                                               # OS temp dir
has TEMP_DIR        => ();                                                                               # SYS_TEMP_DIR/temp-xxxx, random temp dir, created in SYS_TEMP_DIR
has DATA_DIR        => ();

has SCANDEPS  => ();
has DAEMONIZE => ();
has UID       => ();
has GID       => ();

# create $ENV object
$ENV = __PACKAGE__->new;                                                                                 ## no critic qw[Variables::RequireLocalizedPunctuationVars]

_normalize_inc();

$ENV->BUILD1;

_configure_inc();

# TODO - remove??? check under windows
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

        $inc_path = P->path1($inc_path)->to_abs->{path};

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

    # index @INC, resolve @INC paths, remove duplicates, preserve Ref items
    for my $inc_path (@INC) {
        if ( is_ref $inc_path ) {
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
    if ( !$ENV->{is_par} ) {
        my $is_module_build_test = 0;    # $ENV->dist && exists $inc_index->{ $ENV->dist->root . 'blib/lib' } ? 1 : 0;

        # add dist lib and PCORE_LIB to @INC only if we are int on the PAR archive and not in the Module::Build testing environment
        # under Module::Build dist lib is already added and PCORE_LIB is not added to emulate clean CPAN installation
        if ( !$is_module_build_test ) {
            my $dist_lib_path;

            # detect dist lib path
            if ( $ENV->dist && !exists $inc_index->{ $ENV->dist->root . '/lib' } && -d $ENV->dist->root . '/lib' ) {
                $dist_lib_path = $ENV->dist->root . '/lib';

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

sub _init_inline ($self) {
    if ( $self->{is_par} ) {
        $INC{'Inline.pm'} = $INC{'Pcore/Core/Env.pm'};    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

        require XSLoader;

        *Inline::import = sub {
            my $caller = caller;

            XSLoader::load $caller;

            return;
        };
    }
    else {
        require Inline;

        Inline->import(
            config => (
                directory         => $self->{INLINE_DIR},
                autoname          => 0,
                clean_after_build => 1,                     # clean up the current build area if the build was successful
                clean_build_area  => 1,                     # clean up the old build areas within the entire Inline directory
                force_build       => 0,                     # build (compile) the source code every time the program is run
                build_noisy       => 0,                     #  dump build messages to the terminal rather than be silent about all the build details
            )
        );
    }

    return;
}

sub BUILD ( $self, $args ) {
    $self->{is_par} = $ENV{PAR_TEMP} ? 1 : 0;

    $self->{SYS_USER_DIR} = $ENV{HOME} || $ENV{USERPROFILE};

    $self->{PCORE_USER_DIR} = "$self->{SYS_USER_DIR}/.pcore/";
    mkdir $self->{PCORE_USER_DIR} || die qq[Error creating user dir "$self->{PCORE_USER_DIR}"] if !-d $self->{PCORE_USER_DIR};
    if ( !$self->{is_par} ) {
        $self->{INLINE_DIR} = "$self->{PCORE_USER_DIR}inline/$Config{version}-$Config{archname}/";
        mkdir "$self->{PCORE_USER_DIR}inline" || die qq[Error creating ""$self->{PCORE_USER_DIR}inline""] if !-d "$self->{PCORE_USER_DIR}inline";
        mkdir $self->{INLINE_DIR} || die qq[Error creating "$self->{INLINE_DIR}"] if !-d $self->{INLINE_DIR};
    }

    # find Pcore share dir
    my $pcore_path = $INC{'Pcore.pm'};

    # remove "/Pcore.pm"
    substr $pcore_path, -9, 9, '';

    if ( -d "$pcore_path/../share" ) {

        # remove "/lib"
        substr $pcore_path, -4, 4, '';

        $self->{PCORE_SHARE_DIR} = "$pcore_path/share";
    }
    elsif ( -d "$pcore_path/auto/share/dist/Pcore" ) {
        $self->{PCORE_SHARE_DIR} = "$pcore_path/auto/share/dist/Pcore";
    }
    else {
        die q[Pcore share dir can't be found.];
    }

    $self->_init_inline;

    return;
}

sub BUILD1 ($self) {
    $self->{SYS_USER_DIR}   = P->path1( $self->{SYS_USER_DIR} );
    $self->{PCORE_USER_DIR} = P->path1( $self->{PCORE_USER_DIR} );
    $self->{INLINE_DIR}     = P->path1( $self->{INLINE_DIR} ) if $self->{INLINE_DIR};

    # init share
    $self->{share} = Pcore::Core::Env::Share->new;

    $self->{START_DIR} = P->path1->to_abs;

    if ( $Pcore::SCRIPT_PATH eq '-e' || $Pcore::SCRIPT_PATH eq '-' ) {
        $self->{SCRIPT_NAME} = '-e';
        $self->{SCRIPT_DIR}  = $self->{START_DIR};
    }
    else {
        die qq[Cannot find current script "$Pcore::SCRIPT_PATH"] if !-f $Pcore::SCRIPT_PATH;

        my $path = P->path1($Pcore::SCRIPT_PATH)->to_abs;

        $self->{SCRIPT_NAME} = $path->{filename};
        $self->{SCRIPT_DIR}  = $path->{dirname};
    }

    $self->{SCRIPT_PATH} = $self->{SCRIPT_DIR} . $self->{SCRIPT_NAME};

    $self->{SYS_TEMP_DIR} = P->path1( File::Spec->tmpdir );
    $self->{TEMP_DIR} = P->file->tempdir( base => "$self->{SYS_TEMP_DIR}", lazy => 1 );

    # find main dist
    if ( $self->{is_par} ) {
        $self->{main_dist} = Pcore::Dist->new( $ENV{PAR_TEMP} );
    }
    else {
        $self->{main_dist} = Pcore::Dist->new( $self->{SCRIPT_DIR} );
    }

    # register main dist
    if ( $self->{main_dist} ) {
        $self->{main_dist}->{is_main} = 1;

        $self->register_dist( $self->{main_dist} );
    }

    # set DATA_DIR
    if ( my $dist = $self->{main_dist} ) {
        if ( $self->{is_par} ) {
            $self->{DATA_DIR} = $self->{SCRIPT_DIR};
        }
        else {
            $self->{DATA_DIR} = P->path1( $dist->root . '/data' );
            mkdir $self->{DATA_DIR} || die qq[Can't create "$self->{DATA_DIR}"] if !-d $self->{DATA_DIR};
        }
    }
    else {
        $self->{DATA_DIR} = $self->{START_DIR};
    }

    # init pcore dist, required for register pcore resources during bootstrap
    if ( $self->{main_dist} && $self->{main_dist}->is_pcore ) {
        $self->{pcore} = $self->{main_dist};
    }
    else {
        $self->{pcore} = Pcore::Dist->new('Pcore.pm');

        $self->register_dist( $self->{pcore} );
    }

    # scan deps
    if ( !$self->{is_par} && defined( my $dist = $self->{main_dist} ) ) {
        if ( $dist->par_cfg && exists $dist->par_cfg->{ $self->{SCRIPT_NAME} } && !$dist->par_cfg->{ $self->{SCRIPT_NAME} }->{disabled} ) {

            $self->set_scandeps( $dist->share_dir . "pardeps-$self->{SCRIPT_NAME}-@{[$^V->normal]}-$Config{archname}.json" );
        }
    }

    return;
}

# SYS_TEMP_DIR/.pcore
sub get_pcore_sys_dir ($self) {
    state $path = P->path1("$self->{SYS_TEMP_DIR}/.pcore");

    state $init = 0;

    if ( !$init ) {
        $init = 1;

        $path->mkdir if !-d $path;
    }

    return $path;
}

sub set_scandeps ( $self, $path ) {
    $self->{SCANDEPS} = $path;

    return if !$path;

    # eval common modules
    require Cpanel::JSON::XS;    ## no critic qw[Modules::ProhibitEvilModules]

    return;
}

sub _build_user_cfg_path ($self) {
    return "$self->{PCORE_USER_DIR}pcore.ini";
}

sub _build_user_cfg ($self) {
    if ( !-f $self->user_cfg_path ) {
        return {};
    }
    else {
        return P->cfg->read( $self->user_cfg_path );
    }
}

sub register_dist ( $self, $dist ) {

    # create dist object
    $dist = Pcore::Dist->new($dist) if !is_ref $dist;

    # dist was not found
    die qq[Invlaid Pcore -dist pragma usage, "$dist" is not a Pcore dist main module] if !$dist;

    # dist is already registered
    return if exists $self->{_dist_idx}->{ $dist->name };

    # add dist to the dists index
    $self->{_dist_idx}->{ $dist->name } = $dist;

    # register dist share lib
    $self->{share}->register_lib( $dist->name, $dist->share_dir );

    return;
}

sub dist ( $self, $dist_name = undef ) {
    if ($dist_name) {
        return $self->{_dist_idx}->{ $dist_name =~ s/::/-/smgr };
    }
    else {
        return $self->{main_dist};
    }
}

sub DESTROY ( $self ) {
    if ( $self->{SCANDEPS} ) {
        my ( $fh, $index );

        if ( -f $self->{SCANDEPS} ) {
            open $fh, '+<:raw', $self->{SCANDEPS} or die;    ## no critic qw[InputOutput::RequireBriefOpen]

            flock $fh, LOCK_EX or die;

            local $/;

            my $deps = Cpanel::JSON::XS->new->utf8->decode(<$fh>);

            $index->@{ $deps->@* } = ();
        }
        else {
            open $fh, '>:raw', $self->{SCANDEPS} or die;     ## no critic qw[InputOutput::RequireBriefOpen]

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

                    say "new dependency found: $module";
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
## |    3 |                      | Subroutines::ProhibitExcessComplexity                                                                          |
## |      | 206                  | * Subroutine "BUILD1" with high complexity score (23)                                                          |
## |      | 352                  | * Subroutine "DESTROY" with high complexity score (22)                                                         |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 361                  | Variables::RequireInitializationForLocalVars - "local" variable not initialized                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 399                  | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 185, 190             | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 426                  | ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 5                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 117                  | BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                |
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
