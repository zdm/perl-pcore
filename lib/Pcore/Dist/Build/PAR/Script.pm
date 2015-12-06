package Pcore::Dist::Build::PAR::Script;

use Pcore qw[-class];
use Pcore::Util::File::Tree;
use Archive::Zip qw[];
use PAR::Filter;
use Pcore::Src::File;
use Term::ANSIColor qw[:constants];

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );
has arch_deps => ( is => 'ro', isa => HashRef, required => 1 );
has script => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Path'], required => 1 );
has release => ( is => 'ro', isa => Bool,    required => 1 );
has crypt   => ( is => 'ro', isa => Bool,    required => 1 );
has upx     => ( is => 'ro', isa => Bool,    required => 1 );
has clean   => ( is => 'ro', isa => Bool,    required => 1 );
has pardeps => ( is => 'ro', isa => HashRef, required => 1 );
has resources => ( is => 'ro', isa => Maybe [ArrayRef] );

has tree => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::File::Tree'], init_arg => undef );

no Pcore;

sub _build_tree ($self) {
    return Pcore::Util::File::Tree->new;
}

sub run ($self) {

    # add known arch deps packages to the pardeps
    for my $pkg ( $self->arch_deps->{pkg}->@* ) {
        $self->pardeps->{$pkg} = 1;
    }

    # add Filter::Crypto::Decrypt deps if crypt mode is used
    $self->pardeps->{'Filter/Crypto/Decrypt.pm'} = 1 if $self->crypt;

    # add main script
    $self->tree->add_file( 'script/main.pl', $self->script->realpath->to_string );

    # add dist dist.perl
    $self->tree->add_file( 'share/dist.perl', $self->dist->share_dir . '/dist.perl' );

    # add Pcore dist.perl
    $self->tree->add_file( 'lib/auto/share/dist/Pcore/dist.perl', $PROC->res->get_lib('pcore') . 'dist.perl' );

    # add META.yml
    $self->tree->add_file( 'META.yml', P->data->to_yaml( { par => { clean => 1 } } ) ) if $self->clean;

    # add shared libs
    $self->_add_shared_libs;

    # TODO add pardeps
    $self->_add_pardeps;

    # TODO add resources

    my $temp = $self->tree->write_to_temp;

    say $temp;

    # create zipped par
    my $zip_path = $PROC->{TEMP_DIR} . $self->script->filename_base . q[-] . lc $Config::Config{archname} . q[.zip];

    my $zip = Archive::Zip->new;

    $zip->addTree( $temp->path, q[], undef, 9 );

    $zip->writeToFileNamed($zip_path);

    # # create parl executable
    # my $exe_temp_path = $PROC->{TEMP_DIR} . $script->filename_base . q[-] . lc $Config::Config{archname} . q[.exe];
    #
    # `parl -B -O$exe_temp_path $par_path`;

    print 'Press ENTER to continue...';
    <STDIN>;

    return;
}

sub _add_shared_libs ($self) {
    my $processed_so;

    for my $pkg ( keys $self->arch_deps->{so}->%* ) {
        if ( exists $self->pardeps->{$pkg} ) {

            # P->file->mkpath( $par_dir . '/shlib/' . $Config::Config{archname} );

            for my $so ( $self->arch_deps->{so}->{$pkg}->@* ) {
                next if exists $processed_so->{$so};

                $processed_so->{$so} = 1;

                my $so_filename = P->path($so)->filename;

                my $found;

                # find so in the $ENV{PATH}, @INC
                for my $path ( split( /;/sm, $ENV{PATH} ), grep { !ref } @INC ) {
                    if ( -f $path . q[/] . $so ) {
                        $found = $path . q[/] . $so;

                        last;
                    }
                }

                if ($found) {
                    say 'add shared object: ' . $so_filename;

                    $self->tree->add_file( 'shlib/' . $Config::Config{archname} . q[/] . $so_filename, $found );
                }
                else {
                    say BOLD . RED . qq[Shared object wasn't found: "$so_filename"] . RESET;
                }
            }
        }
    }

    return;
}

sub _add_pardeps ($self) {
    for my $pkg ( grep {/[.](?:pl|pm)\z/sm} keys $self->pardeps->%* ) {
        my $found = $self->_add_pkg($pkg);

        say BOLD . RED . 'not found: ' . $pkg . RESET if !$found && $deps->{$pkg} !~ /\A[(]eval\s/sm;
    }

    return;
}

sub _add_pkg ( $self, $pkg ) {
    my $found;

    my $pkg_path = P->path($pkg);

    if ( $found = $self->_find_module($pkg) ) {
        my $inc_path = $found->[0];

        # packages without so placed in /lib/, with so placed in /<current_arch>/
        my $package_target_path = 'lib/';

        # find and add shared libs
        my $pkg_auto_path = 'auto/' . $pkg_path->dirname . $pkg_path->filename_base . q[/];

        my $pkg_inc_so_path = $inc_path . q[/] . $pkg_auto_path . $pkg_path->filename_base . q[.] . $Config::Config{dlext};

        # package has auto path
        if ( -d $inc_path . q[/] . $pkg_auto_path ) {

            # package has shared object
            if ( -f $pkg_inc_so_path ) {
                $package_target_path = $Config::Config{version} . q[/] . $Config::Config{archname} . q[/];

                # copy shared object
                $self->_copy_file( $pkg_inc_so_path, $par_dir . $package_target_path . $pkg_auto_path . $pkg_path->filename_base . q[.] . $Config::Config{dlext} );

                # compress shared object with upx
                $self->_upx( $par_dir . $package_target_path . $pkg_auto_path . $pkg_path->filename_base . q[.] . $Config::Config{dlext} ) if !$profile->{noupx};
            }

            # add .ix, .al
            P->file->copy( qq[$inc_path/$pkg_auto_path/], qq[$par_dir/$package_target_path/$pkg_auto_path/], glob => q[*.ix] );

            P->file->copy( qq[$inc_path/$pkg_auto_path/], qq[$par_dir/$package_target_path/$pkg_auto_path/], glob => q[*.al] );
        }

        # find package inline deps
        my $pkg_inline_so_path = $PROC->{INLINE_DIR} . q[lib/auto/] . $pkg_path->dirname . $pkg_path->filename_base . q[/] . $pkg_path->filename_base . q[.];

        if ( -f $pkg_inline_so_path . $Config::Config{dlext} ) {    # package has inline deps
            $package_target_path = $Config::Config{version} . q[/] . $Config::Config{archname} . q[/];

            my $package_inline_target_path = $par_dir . $package_target_path . q[auto/] . $pkg_path->dirname . $pkg_path->filename_base . q[/] . $pkg_path->filename_base . q[.];

            # copy inline shared object
            $self->_copy_file( $pkg_inline_so_path . $Config::Config{dlext}, $package_inline_target_path . $Config::Config{dlext} );

            # compress inline shared object with upx
            $self->_upx( $package_inline_target_path . $Config::Config{dlext} ) if !$profile->{noupx};

            # copy inline metadata
            $self->_copy_file( $pkg_inline_so_path . 'inl', $package_inline_target_path . 'inl' );

            # copy inline config file
            my $inline_config_name = 'config-' . $Config::Config{archname} . q[-] . $];

            my $inline_config_target_path = $par_dir . $package_target_path . $inline_config_name;

            $self->_copy_file( $PROC->{INLINE_DIR} . $inline_config_name, $inline_config_target_path ) if !-f $inline_config_target_path;
        }

        $self->_add_perl_source( $inc_path . q[/] . $pkg, $par_dir . $package_target_path . $pkg, $profile, $pkg, $found->[1] );
    }

    return $found;
}

sub _find_module ( $self, $module ) {
    state $perl_inc = do {
        my $index;

        for my $var (qw[privlibexp archlibexp sitelibexp sitearchexp vendorlibexp vendorarchexp]) {
            $index->{ P->path( $Config::Config{$var}, is_dir => 1 )->canonpath } = 1;
        }

        $index;
    };

    # directly use './lib/' because dist can be located outside @INC
    for my $inc_path ( grep { !ref } './lib/', @INC ) {
        if ( -f $inc_path . q[/] . $module ) {
            return [ $inc_path, $perl_inc->{$inc_path} // 0 ];
        }
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
## │    3 │ 85, 124              │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 101, 150, 172, 213   │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::PAR::Script

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
