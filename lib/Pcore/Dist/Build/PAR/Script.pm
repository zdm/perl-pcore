package Pcore::Dist::Build::PAR::Script;

use Pcore qw[-class];
use Pcore::Util::File::Tree;
use Archive::Zip qw[];
use PAR::Filter;
use Filter::Crypto::CryptFile;
use Pcore::Src::File;
use Term::ANSIColor qw[:constants];

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );
has par_deps  => ( is => 'ro', isa => ArrayRef, required => 1 );
has arch_deps => ( is => 'ro', isa => HashRef,  required => 1 );
has script => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Path'], required => 1 );
has release     => ( is => 'ro', isa => Bool,    required => 1 );
has crypt       => ( is => 'ro', isa => Bool,    required => 1 );
has upx         => ( is => 'ro', isa => Bool,    required => 1 );
has clean       => ( is => 'ro', isa => Bool,    required => 1 );
has script_deps => ( is => 'ro', isa => HashRef, required => 1 );
has resources => ( is => 'ro', isa => Maybe [ArrayRef] );

has tree => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::File::Tree'], init_arg => undef );

no Pcore;

sub _build_tree ($self) {
    return Pcore::Util::File::Tree->new;
}

sub run ($self) {

    # add common par deps packages to the script_deps
    for my $pkg ( $self->par_deps->@* ) {
        $self->script_deps->{$pkg} = 1;
    }

    # add known arch deps packages to the script_deps
    for my $pkg ( $self->arch_deps->{pkg}->@* ) {
        $self->script_deps->{$pkg} = 1;
    }

    # add Filter::Crypto::Decrypt deps if crypt mode is used
    $self->script_deps->{'Filter/Crypto/Decrypt.pm'} = 1 if $self->crypt;

    # add main script
    $self->_add_perl_source( $self->script->realpath->to_string, 'script/main.pl' );

    # add dist dist.perl
    $self->tree->add_file( 'share/dist.perl', $self->dist->share_dir . '/dist.perl' );

    # add Pcore dist.perl
    $self->tree->add_file( 'lib/auto/share/dist/Pcore/dist.perl', $PROC->res->get_lib('pcore') . 'dist.perl' );

    # add META.yml
    $self->tree->add_file( 'META.yml', P->data->to_yaml( { par => { clean => 1 } } ) ) if $self->clean;

    # add shared libs
    $self->_add_shared_libs;

    # process script deps
    $self->_add_script_deps;

    # TODO add resources

    my $temp = $self->tree->write_to_temp;

    # set permissions, remove read-only attribute for windows
    my @compress_upx;

    P->file->find(
        $temp->path,
        dir => 0,
        sub ($path) {
            if ($MSWIN) {
                require Win32::File;

                Win32::File::SetAttributes( $path, Win32::File::NORMAL() ) or die;
            }
            else {
                P->file->chmod( 'rw-------', $path );
            }

            # compress with upx
            if ( $path =~ /$Config::Config{dlext}\z/sm ) {
                push @compress_upx, $path->realpath;
            }

            return;
        }
    );

    $self->_compress_upx( \@compress_upx ) if $self->upx && @compress_upx;

    say $temp;

    # create zipped par
    my $zip = Archive::Zip->new;

    $zip->addTree(
        {   root             => $temp->path,
            zipName          => q[],
            compressionLevel => 9,
        }
    );

    my $zip_path = $PROC->{TEMP_DIR} . $self->script->filename_base . q[-] . lc $Config::Config{archname} . q[.zip];

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
        if ( exists $self->script_deps->{$pkg} ) {
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

sub _add_script_deps ($self) {
    for my $pkg ( grep {/[.](?:pl|pm)\z/sm} keys $self->script_deps->%* ) {
        my $found = $self->_add_pkg($pkg);

        say BOLD . RED . 'not found: ' . $pkg . RESET if !$found && $self->script_deps->{$pkg} !~ /\A[(]eval\s/sm;
    }

    return;
}

sub _add_pkg ( $self, $pkg ) {
    $pkg = P->path($pkg);

    my $inc_path;

    my $located_in_cpan;

    # directly use './lib/' because dist can be located outside @INC
    for ( grep { !ref } $self->dist->root . 'lib/', @INC ) {
        if ( -f ( $_ . q[/] . $pkg ) ) {
            $inc_path = P->path( $_, is_dir => 1 );

            $located_in_cpan = $inc_path->canonpath ~~ $self->dist->cpan_path ? 1 : 0;

            last;
        }
    }

    # package wasn't found
    return if !$inc_path;

    my $target_base = 'lib/';

    my $auto_base = 'auto/' . $pkg->dirname . $pkg->filename_base . q[/];

    # find package shared objects
    if ($located_in_cpan) {
        if ( -d $inc_path . $auto_base ) {
            my $pkg_so_filename = $pkg->filename_base . q[.] . $Config::Config{dlext};

            my $pkg_so_source_path = $inc_path . $auto_base . $pkg_so_filename;

            if ( -f $pkg_so_source_path ) {

                # package has shared object in CPAN
                $target_base = $Config::Config{version} . q[/] . $Config::Config{archname} . q[/];

                $self->tree->add_file( $target_base . $auto_base . $pkg_so_filename, $pkg_so_source_path );

                # add .ix, .al
                P->file->find(
                    $inc_path . $auto_base,
                    dir => 0,
                    sub ($path) {
                        if ( $path->suffix eq 'ix' || $path->suffix eq 'al' ) {
                            $self->tree->add_file( $target_base . $auto_base . $path, $inc_path . $auto_base . $path );
                        }

                        return;
                    }
                );
            }
        }
    }

    # find package inline deps
    my $pkg_inline_source_base = $PROC->{INLINE_DIR} . q[lib/auto/] . $pkg->dirname . $pkg->filename_base . q[/] . $pkg->filename_base . q[.];

    # package has inline shared object
    if ( -f $pkg_inline_source_base . $Config::Config{dlext} ) {
        $target_base = $Config::Config{version} . q[/] . $Config::Config{archname} . q[/];

        my $pkg_inline_target_base = $target_base . q[auto/] . $pkg->dirname . $pkg->filename_base . q[/] . $pkg->filename_base . q[.];

        # add inline shared object
        $self->tree->add_file( $pkg_inline_target_base . $Config::Config{dlext}, $pkg_inline_source_base . $Config::Config{dlext} );

        $self->tree->add_file( $pkg_inline_target_base . 'inl', $pkg_inline_source_base . 'inl' );

        # add global inline config file
        my $inline_config_name = 'config-' . $Config::Config{archname} . q[-] . $];

        $self->tree->add_file( $target_base . $inline_config_name, $PROC->{INLINE_DIR} . $inline_config_name );
    }

    # add .pm to the files tree
    $self->_add_perl_source( $inc_path . $pkg, $target_base . $pkg, $located_in_cpan, $pkg );

    return 1;
}

# TODO patch pod with version info:
# pcore version, changeset id
# dist version, changeset id
# build date, UTC
sub _add_perl_source ( $self, $source, $target, $located_in_cpan = 0, $pkg = undef ) {
    my $src = P->file->read_bin($source);

    if ($pkg) {

        # patch content for PAR compatibility
        $src = PAR::Filter->new('PatchContent')->apply( $src, $pkg->to_string );

        # this is perl core or CPAN module
        if ($located_in_cpan) {
            if ( $self->release ) {
                $src = Pcore::Src::File->new(
                    {   action      => 'compress',
                        path        => $target,
                        is_realpath => 0,
                        in_buffer   => $src,
                        filter_args => {             #
                            perl_compress => 1,
                        },
                    }
                )->run->out_buffer;
            }
            else {
                $src = Pcore::Src::File->new(
                    {   action      => 'compress',
                        path        => $target,
                        is_realpath => 0,
                        in_buffer   => $src,
                        filter_args => {
                            perl_strip_maintain_linum => 1,
                            perl_strip_comment        => 1,
                            perl_strip_pod            => 1,
                        },
                    }
                )->run->out_buffer;
            }

            $self->tree->add_file( $target, $src );

            return;
        }
    }

    my $crypt = $self->crypt && ( !$pkg || $pkg ne 'Filter/Crypto/Decrypt.pm' );

    # we don't compress sources for devel build, preserving line numbers
    if ( !$self->release ) {
        $src = Pcore::Src::File->new(
            {   action      => 'compress',
                path        => $target,
                is_realpath => 0,
                in_buffer   => $src,
                filter_args => {
                    perl_strip_maintain_linum => 1,
                    perl_strip_comment        => 1,
                    perl_strip_pod            => 1,
                },
            }
        )->run->out_buffer;
    }
    else {
        if ($crypt) {

            # for crypted release - only strip sources without preserving line numbers, Filter::Crypto::Decrypt isn't work with compressed sources
            $src = Pcore::Src::File->new(
                {   action      => 'compress',
                    path        => $target,
                    is_realpath => 0,
                    in_buffer   => $src,
                    filter_args => {
                        perl_strip_maintain_linum => 0,
                        perl_strip_comment        => 1,
                        perl_strip_pod            => 1,
                    },
                }
            )->run->out_buffer;
        }
        else {

            # for not crypted release - compress all sources
            $src = Pcore::Src::File->new(
                {   action      => 'compress',
                    path        => $target,
                    is_realpath => 0,
                    in_buffer   => $src,
                    filter_args => {             #
                        perl_compress => 1,
                    },
                }
            )->run->out_buffer;
        }
    }

    # crypt sources, if nedeed
    if ($crypt) {
        open $crypt_in_fh, '<', $src or die;

        open $crypt_out_fh, '<', \my $crypted_src or die;

        Filter::Crypto::CryptFile::crypt_file( $crypt_in_fh, $crypt_out_fh, Filter::Crypto::CryptFile::CRYPT_MODE_ENCRYPTED() );

        close $crypt_in_fh or die;

        close $crypt_out_fh or die;

        $src = $crypted_src;
    }

    $self->tree->add_file( $target, $src );

    return;
}

sub _compress_upx ( $self, $path ) {
    my $upx;

    if ($MSWIN) {
        $upx = $PROC->res->get('/bin/upx.exe');
    }
    else {
        $upx = $PROC->res->get('/bin/upx_x64');
    }

    P->sys->system( $upx, '--best', $path->@* ) or 1 if $upx;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 124, 160             │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 137, 196, 228        │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 254                  │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
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
