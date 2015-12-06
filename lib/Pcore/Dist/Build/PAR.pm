package Pcore::Dist::Build::PAR;

use Pcore qw[-class];
use Config qw[];
use Pcore::Dist::Build::PAR::Script;
use Term::ANSIColor qw[:constants];

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has release => ( is => 'ro', isa => Bool, default => 0 );
has crypt   => ( is => 'ro', isa => Bool, default => 0 );
has upx     => ( is => 'ro', isa => Bool, default => 1 );
has clean   => ( is => 'ro', isa => Bool, default => 1 );

no Pcore;

# sub _build_dist_version ($self) {
#     return $self->dist->version;
# }
#
# sub _build_build_version ($self) {
#     return P->date->now_utc->strftime('%Y%m%d%H%M%S');
# }

sub run ($self) {

    # load .pardeps.cbor
    my $pardeps;

    if ( -f $self->dist->root . 'data/.pardeps.cbor' ) {
        $pardeps = P->cfg->load( $self->dist->root . 'data/.pardeps.cbor' );
    }
    else {
        say q["data/.pardeps.cbor" is not exists.];

        say q[Run source scripts with --scan-deps argument.];

        exit 1;
    }

    # check for distribution has configure PAR profiles in dist.perl
    if ( !$self->dist->cfg->{dist}->{par} && !ref $self->dist->cfg->{dist}->{par} eq 'HASH' ) {
        say q[par profile wasn't found.];

        exit 1;
    }

    # load global pcore.perl config
    my $pcore_cfg = P->cfg->load( $PROC->res->get( '/data/pcore.perl', lib => 'pcore' ) );

    # build scripts
    for my $script ( sort keys $self->dist->cfg->{dist}->{par}->%* ) {
        $script = P->path($script);

        my $profile = $self->dist->cfg->{dist}->{par}->{$script};

        $profile->{dist} = $self->dist;

        $profile->{par_deps} = $pcore_cfg->{par_deps} // [];

        $profile->{arch_deps} = $pcore_cfg->{arch_deps}->{ $Config::Config{archname} } // {};

        $profile->{script} = $script;

        $profile->{release} = $self->release;

        $profile->{crypt} = $self->crypt if defined $self->crypt;

        $profile->{upx} = $self->upx if defined $self->upx;

        $profile->{clean} = $self->clean if defined $self->clean;

        if ( !exists $pardeps->{ $script->filename }->{ $Config::Config{archname} } ) {
            say BOLD . RED . qq[Deps for $script "$Config::Config{archname}" wasn't scanned.] . RESET;

            say qq[Run "$script ---scan-deps"];

            next;
        }
        else {
            $profile->{script_deps} = $pardeps->{ $script->filename }->{ $Config::Config{archname} };
        }

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
## │    3 │ 52                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
sub _build_script ( $self, $script, $profile ) {
    $script = P->path($script);

    my $exe_path = 'data/' . $script->filename_base . ( $Config::Config{archname} =~ /x64|x86_64/sm ? q[-x64] : q[] );
    $exe_path .= $profile->{release} ? q[-] . $self->dist_version . q[.] . $self->build_version : q[-devel];
    $exe_path .= $MSWIN ? q[.exe] : q[];

    say BOLD . GREEN . qq[\nbuild] . ( $profile->{crypt} ? ' crypted' : BOLD . RED . q[ not crypted] . BOLD . GREEN ) . qq[ "$exe_path" for $Config::Config{archname}] . RESET;

    if ( !$self->_pardeps->{ $script->filename }->{ $Config::Config{archname} } ) {
        say BOLD . RED . qq[Deps for "$Config::Config{archname}" wasn't scanned.] . RESET;

        say qq[Run "$script ---scan-deps"];

        return;
    }

    my $par_dir = P->file->tempdir;

    P->file->mkdir( $par_dir . 'lib/' );

    # add known platform deps
    my $deps = $self->_pardeps->{ $script->filename }->{ $Config::Config{archname} };

    for my $pkg ( $PAR_CFG->{known_deps}->{ $Config::Config{archname} }->{pkg}->@* ) {
        $deps->{$pkg} = 1;
    }

    # add Filter::Crypto::Decrypt deps if crypt mode used
    $deps->{'Filter/Crypto/Decrypt.pm'} = 1 if $profile->{crypt};

    # find and copy perl sources to temporary location
    for my $pkg ( grep {/[.](?:pl|pm)\z/sm} keys $deps->%* ) {
        my $found = $self->_add_pkg( $pkg, $par_dir, $profile );

        say BOLD . RED . 'not found: ' . $pkg . RESET if !$found && $deps->{$pkg} !~ /\A[(]eval\s/sm;
    }

    # copy main script
    $self->_add_perl_source( $script, $par_dir . 'script/main.pl', $profile );

    # copy current dist dist.perl
    $self->_copy_file( 'share/dist.perl', $par_dir . 'script/dist.perl' );

    # find and add shared libs
    my $processed_so;

    for my $pkg ( keys $PAR_CFG->{known_deps}->{ $Config::Config{archname} }->{so}->%* ) {
        if ( exists $deps->{$pkg} ) {
            P->file->mkpath( $par_dir . '/shlib/' . $Config::Config{archname} );

            for my $so ( $PAR_CFG->{known_deps}->{ $Config::Config{archname} }->{so}->{$pkg}->@* ) {
                next if exists $processed_so->{$so};

                $processed_so->{$so} = 1;

                my $so_filename = P->path($so)->filename;

                my $found;

                for my $path ( split( /;/sm, $ENV{PATH} ), @INC ) {
                    if ( -f $path . q[/] . $so ) {
                        $found = $path . q[/] . $so;

                        last;
                    }
                }

                if ($found) {
                    say 'add shared object: ' . $so_filename;

                    P->file->copy( $found, $par_dir . '/shlib/' . $Config::Config{archname} . q[/] . $so_filename );

                    $self->_upx( $par_dir . '/shlib/' . $Config::Config{archname} . q[/] . $so_filename ) if !$profile->{noupx};
                }
                else {
                    say BOLD . RED . qq[Shared object wasn't found: "$so_filename"] . RESET;
                }
            }
        }
    }

    # add pcore share dir
    P->file->copy( $PROC->res->get_lib('pcore'), $par_dir . 'lib/auto/share/dist/Pcore/' );

    # add current dist share dir
    P->file->copy( './share/', $par_dir . 'lib/auto/share/dist/' . $self->dist->cfg->{dist}->{name} . q[/] );

    # add resources
    print 'add resources ... ';

    if ( $profile->{resources} && $profile->{resources}->@* ) {

        # add dist resources dir manually, because it is not added during Pcore bootstrap
        unshift P->res->get_root->@*, './resources/' if -d './resources/';

        for my $resource ( $profile->{resources}->@* ) {
            my $method = q[copy_] . $resource->[0];

            P->res->$method( $resource->[1], $par_dir . 'resources/' );
        }
    }

    say 'done';

    # create META.yml
    P->cfg->store( $par_dir . 'META.yml', { par => { clean => 1 } }, to => 'yaml' ) if $profile->{clean};

    # create zipped par
    my $par_path = $PROC->{TEMP_DIR} . $script->filename_base . q[-] . lc $Config::Config{archname} . q[.zip];

    my $zip = Archive::Zip->new;

    $zip->addTree( $par_dir->path, q[], undef, 9 );

    $zip->writeToFileNamed($par_path);

    # create parl executable
    my $exe_temp_path = $PROC->{TEMP_DIR} . $script->filename_base . q[-] . lc $Config::Config{archname} . q[.exe];

    `parl -B -O$exe_temp_path $par_path`;

    $self->_repack_par( $exe_temp_path, $exe_path, $profile, $zip );

    return;
}

1;
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
