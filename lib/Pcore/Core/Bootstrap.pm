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

    # register util accessors
    P->hash->merge( $Pcore::Core::Util::UTIL, $PROC->{CFG}->{util} ) if $PROC->{CFG}->{util};

    _configure_inc();

    _configure_inline();

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

        next if $inc_path eq q[.];    # ignore relative script path, added by perl automatically

        next if !-d $inc_path;

        $inc_path = P->path( $inc_path, is_dir => 1 )->realpath->canonpath;

        if ( !exists $inc_index->{$inc_path} ) {
            $inc_index->{$inc_path} = 1;

            push @inc, $inc_path;
        }
    }

    if ( !$PROC->is_par ) {
        my $dist_lib_path;

        # add dist lib path
        if ( $PROC->dist && -d $PROC->dist->root . 'lib/' && !exists $inc_index->{ $PROC->dist->root . 'lib' } ) {
            $dist_lib_path = $PROC->dist->root . 'lib';

            $inc_index->{$dist_lib_path} = 1;
        }

        # find and add other dist libs to @INC
        if ( $ENV{PCORE_DIST_LIB} && -d $ENV{PCORE_DIST_LIB} ) {
            for my $dir ( P->file->read_dir( $ENV{PCORE_DIST_LIB}, full_path => 1 )->@* ) {
                if ( !exists $inc_index->{qq[$dir/lib]} && -d qq[$dir/lib/] && Pcore::Dist->dir_is_dist($dir) ) {
                    $inc_index->{qq[$dir/lib]} = 1;

                    unshift @inc, qq[$dir/lib];
                }
            }
        }

        # register dist lib path in @INC, dist lib path is always on top of other dists
        unshift @inc, $dist_lib_path if $dist_lib_path;

        # add absolute script path, only if not in PAR mode
        my $script_path = P->path( $PROC->{SCRIPT_DIR}, is_dir => 1 )->canonpath;

        if ( !exists $inc_index->{$script_path} ) {
            $inc_index->{$script_path} = 1;

            push @inc, $script_path;
        }
    }

    @INC = @inc;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return;
}

sub _configure_inline {
    P->file->mkpath( $PROC->{INLINE_DIR} ) if !-d $PROC->{INLINE_DIR};

    require Inline;

    Inline->import(
        config => (
            directory         => $PROC->{INLINE_DIR},
            autoname          => 0,
            clean_after_build => 1,
            clean_build_area  => 1,
        )
    );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 11                   │ ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              │
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
