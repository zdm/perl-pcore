package Pcore::Core::Bootstrap;

use Pcore;
use File::Spec qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use File::ShareDir qw[];
use Config qw[];
use Cwd qw[];           ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::Core::Proc;

# may not work, if executed in one-liner script
eval { require FindBin; };

if ($@) {
    $FindBin::Bin = $FindBin::RealBin = Cwd::getcwd();

    $FindBin::Script = $FindBin::RealScript = $0 =~ s[\A.*?[/\\](.+)\z][$1]smr;

    # prevent attempts to reload FindBin later
    delete $INC{'FindBin.pm'};

    $INC{'FindBin.pm'} = 'eval()';    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
}

sub CORE_INIT ($proc_cfg) {
    $PROC = Pcore::Core::Proc->new( $proc_cfg // () );

    _configure_dist();

    _configure_p();

    # register util accessors
    P->hash->merge( $Pcore::Core::Util::UTIL, $P->{util} )    if $P->{util};
    P->hash->merge( $Pcore::Core::Util::UTIL, $DIST->{util} ) if $DIST->{util};

    _configure_inc();

    _configure_inline();

    return;
}

sub _configure_dist {
    $DIST = {};

    if ($Pcore::IS_PAR) {    # script located in temp PAR archive
        $DIST = P->cfg->load( $ENV{PAR_TEMP} . '/inc/script/dist.perl' );

        my $dist_share_dir = eval {
            local $SIG{__DIE__} = undef;

            File::ShareDir::dist_dir( $DIST->{dist}->{name} );
        };

        $DIST->{ROOT}      = q[];
        $DIST->{SHARE_DIR} = $dist_share_dir ? P->path( $dist_share_dir, is_dir => 1 )->realpath->to_string : q[];
        $DIST->{LOG_DIR}   = P->path( $ENV{PAR_TEMP} . '/log/', is_dir => 1, lazy => 1 );
        $DIST->{DATA_DIR}  = q[];
    }
    elsif ( my $dist_root = find_dist_root( $PROC->{SCRIPT_DIR} ) ) {    # script located in dist location
        $DIST = P->cfg->load( $dist_root . 'share/dist.perl' );

        $DIST->{ROOT}      = $dist_root->to_string;
        $DIST->{SHARE_DIR} = $DIST->{ROOT} . 'share/';
        $DIST->{LOG_DIR}   = P->path( $DIST->{ROOT} . 'log/', is_dir => 1, lazy => 1 );
        $DIST->{DATA_DIR}  = P->path( $DIST->{ROOT} . 'data/', is_dir => 1, lazy => 1 );
    }
    else {                                                               # script located in unknown location
        $DIST->{ROOT}      = q[];
        $DIST->{SHARE_DIR} = q[];
        $DIST->{LOG_DIR}   = q[];
        $DIST->{DATA_DIR}  = q[];
    }

    # create $DIST share dir shortcuts
    if ( $DIST->{SHARE_DIR} ) {
        $DIST->{TMPL_DIR} = -d $DIST->{SHARE_DIR} . 'tmpl/' ? $DIST->{SHARE_DIR} . 'tmpl/' : q[];
        $DIST->{I18N_DIR} = -d $DIST->{SHARE_DIR} . 'i18n/' ? $DIST->{SHARE_DIR} . 'i18n/' : q[];
    }

    return;
}

sub _configure_p {
    $P = {};

    my $p_root = P->path( $INC{'Pcore.pm'} =~ s[[\\/]lib[\\/]Pcore[.]pm\z][]smr, is_dir => 1 )->realpath;

    if ( _dir_is_dist_root($p_root) ) {    # Pcore is deployed as dist
        if ( $DIST->{ROOT} && $DIST->{ROOT} eq $p_root ) {    # Pcore is current dist
            $P = $DIST;

            $DIST->{IS_PCORE} = 1;
        }
        else {                                                # Pcore dist is separate
            $P = P->cfg->load( $p_root . 'share/dist.perl' );

            $P->{ROOT}      = $p_root;
            $P->{SHARE_DIR} = $P->{ROOT} . 'share/';
        }

        # define inline dir location
        $P->{INLINE_DIR} = P->path( $P->{ROOT} . '.inline/' . $Config::Config{version} . q[/] . $Config::Config{archname} . q[/], is_dir => 1, lazy => 1 );
    }
    else {                                                    # Pcore is located in CPAN or in PAR
        my $p_share_dir = P->path( File::ShareDir::dist_dir('Pcore'), is_dir => 1 )->realpath->to_string;

        $P = P->cfg->load( $p_share_dir . 'dist.perl' );

        $P->{ROOT}      = q[];
        $P->{SHARE_DIR} = $p_share_dir;

        # define inline dir location
        if ($Pcore::IS_PAR) {                                 # Pcore PAR inline dir location
            $P->{INLINE_DIR} = P->path( $ENV{PAR_TEMP} . '/inc/' . $Config::Config{version} . q[/] . $Config::Config{archname} . q[/], is_dir => 1, lazy => 1 );
        }
        else {                                                # Pcore CPAN inline dir location
            $P->{INLINE_DIR} = P->path( $P->{SHARE_DIR} . '.inline/', is_dir => 1, lazy => 1 );
        }
    }

    # create $P share dir shortcuts
    if ( $P->{SHARE_DIR} ) {
        $P->{TMPL_DIR} = -d $P->{SHARE_DIR} . 'tmpl/' ? $P->{SHARE_DIR} . 'tmpl/' : q[];
        $P->{I18N_DIR} = -d $P->{SHARE_DIR} . 'i18n/' ? $P->{SHARE_DIR} . 'i18n/' : q[];
    }

    return;
}

sub _configure_inc {
    my @inc;
    my $inc_index;

    # index @INC, resolve @INC paths, remove duplicates, preserve CODE items
    for my $inc_path (@INC) {
        if ( ref $inc_path eq 'CODE' ) {
            push @inc, $inc_path;

            next;
        }

        next if $inc_path eq q[.];    # ignore relative script path, added by perl automatically

        next if !-d $inc_path;

        $inc_path = P->path( $inc_path, is_dir => 1 )->realpath->canonpath;

        if ( !exists $inc_index->{$inc_path} ) {
            $inc_index->{$inc_path} = 1;

            push @inc, $inc_path;
        }
    }

    if ( !$Pcore::IS_PAR ) {
        my $dist_lib_path;

        if ( $DIST->{ROOT} && -d $DIST->{ROOT} . 'lib/' && !exists $inc_index->{ $DIST->{ROOT} . 'lib' } ) {
            $dist_lib_path = $DIST->{ROOT} . 'lib';

            $inc_index->{$dist_lib_path} = 1;
        }

        # find and add other dist libs to @INC
        if ( $ENV{PCORE_DIST_LIB} && -d $ENV{PCORE_DIST_LIB} ) {
            for my $dir ( P->file->read_dir( $ENV{PCORE_DIST_LIB}, full_path => 1 )->@* ) {
                if ( !exists $inc_index->{qq[$dir/lib]} && -d qq[$dir/lib/] && _dir_is_dist_root($dir) ) {
                    $inc_index->{qq[$dir/lib]} = 1;

                    unshift @inc, qq[$dir/lib];
                }
            }
        }

        # register dist lib path in @INC, dist lib path is always on top of other dists
        unshift @inc, $dist_lib_path if $dist_lib_path;

        # add absolute script path, only if not in PAR mode
        my $path = P->path( $PROC->{SCRIPT_DIR}, is_dir => 1 )->canonpath;

        if ( !exists $inc_index->{$path} ) {
            $inc_index->{$path} = 1;

            push @inc, $path;
        }
    }

    @INC = @inc;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return;
}

sub _configure_inline {
    P->file->mkpath( $P->{INLINE_DIR} ) if !-d $P->{INLINE_DIR};

    require Inline;

    Inline->import(
        config => (
            directory         => $P->{INLINE_DIR},
            autoname          => 0,
            clean_after_build => 1,
            clean_build_area  => 1,
        )
    );

    return;
}

# find dist root in current dir and all parent dirs
sub find_dist_root {
    my $dir = P->path(shift);

    while ($dir) {
        return $dir if _dir_is_dist_root($dir);

        $dir = $dir->parent;
    }

    return;
}

# check, is current dir is a dist root
sub _dir_is_dist_root {
    my $dir = shift;

    if ( -f $dir . '/share/dist.perl' ) {
        return 1;
    }
    else {
        return;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 11                   │ ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 227                  │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Bootstrap

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
