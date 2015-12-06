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
has par_suffix   => ( is => 'lazy', isa => Str, init_arg => undef );
has exe_filename => ( is => 'lazy', isa => Str, init_arg => undef );

no Pcore;

sub _build_tree ($self) {
    return Pcore::Util::File::Tree->new;
}

sub _build_par_suffix ($self) {
    return $MSWIN ? '.exe' : q[];
}

sub _build_exe_filename ($self) {
    my $filename = $self->script->filename_base;

    my @attrs;

    if ( $self->release ) {
        push @attrs, $self->dist->version;
    }
    else {
        push @attrs, 'devel';
    }

    push @attrs, 'x64' if $Config::Config{archname} =~ /x64|x86_64/sm;

    return $filename . q[-] . join( q[-], @attrs ) . $self->par_suffix;
}

sub run ($self) {
    say BOLD . GREEN . qq[\nbuild] . ( $self->crypt ? ' crypted' : BOLD . RED . q[ not crypted] . BOLD . GREEN ) . qq[ "@{[$self->exe_filename]}" for $Config::Config{archname}] . RESET;

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
    print 'adding deps ... ';
    $self->_add_script_deps;
    say 'done';

    $self->_add_resources;

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
            if ( $path =~ /\Q$Config::Config{so}\E\z/sm ) {
                push @compress_upx, $path->realpath;
            }

            return;
        }
    );

    $self->_compress_upx( \@compress_upx ) if $self->upx && @compress_upx;

    # create zipped par
    my $zip = Archive::Zip->new;

    $zip->addTree(
        {   root             => $temp->path,
            zipName          => q[],
            compressionLevel => 9,
        }
    );

    my $zip_fh = P->file->tempfile( suffix => 'zip' );

    $zip->writeToFileHandle($zip_fh);

    $zip_fh->close;

    # create parl executable
    my $parl_path = P->file->temppath( suffix => $self->par_suffix );

    print 'write parl ... ';

    my $cmd = qq[parl -B -O$parl_path ] . $zip_fh->path;

    `$cmd` or die;

    say 'done';

    my $repacked_path = $self->_repack_parl( $parl_path, $zip );

    my $target_exe = $self->dist->root . 'data/' . $self->exe_filename;

    P->file->move( $repacked_path, $target_exe );

    P->file->chmod( 'r-x------', $target_exe );

    say 'final binary size: ' . BOLD . GREEN . ( reverse join q[_], ( reverse -s $target_exe ) =~ /(\d{1,3})/smg ) . RESET . ' bytes';

    return;
}

sub _add_resources ($self) {
    return if !$self->resources;

    for my $res ( $self->resources->@* ) {
        my $path = $PROC->res->get($res);

        if ( !$path ) {
            $self->_error(qq[required resource "$res" wasn't found]);
        }
        else {
            say qq[resource added: "$res"];

            $self->tree->add_file( 'share/' . $res, $path );
        }
    }

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
                    say qq[shared lib added: "$so_filename"];

                    $self->tree->add_file( 'shlib/' . $Config::Config{archname} . q[/] . $so_filename, $found );
                }
                else {
                    $self->_error(qq[shared object wasn't found: "$so_filename"]);
                }
            }
        }
    }

    return;
}

sub _add_script_deps ($self) {
    for my $pkg ( grep {/[.](?:pl|pm)\z/sm} keys $self->script_deps->%* ) {
        my $found = $self->_add_pkg($pkg);

        $self->_error(qq[required deps wasn't found: $pkg]) if !$found && $self->script_deps->{$pkg} !~ /\A[(]eval\s/sm;
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
        open my $crypt_in_fh, '<', $src or die;

        open my $crypt_out_fh, '+>', \my $crypted_src or die;

        Filter::Crypto::CryptFile::crypt_file( $crypt_in_fh, $crypt_out_fh, Filter::Crypto::CryptFile::CRYPT_MODE_ENCRYPTED() );

        close $crypt_in_fh or die;

        close $crypt_out_fh or die;

        $src = \$crypted_src;
    }

    $self->tree->add_file( $target, $src );

    return;
}

sub _compress_upx ( $self, $path ) {
    my $upx;

    my $upx_cache_dir = $PROC->{SYS_TEMP_DIR} . '.pcore/upx-cache/';

    if ($MSWIN) {
        $upx = $PROC->res->get('/bin/upx.exe');
    }
    else {
        $upx = $PROC->res->get('/bin/upx_x64');
    }

    if ($upx) {
        P->file->mkpath($upx_cache_dir);

        my @files;

        my $file_md5 = {};

        for my $file ( $path->@* ) {
            $file_md5->{$file} = Digest::MD5->new->add( P->file->read_bin($file)->$* )->hexdigest;

            if ( -e $upx_cache_dir . $file_md5->{$file} ) {
                P->file->copy( $upx_cache_dir . $file_md5->{$file}, $file );
            }
            else {
                push @files, $file;
            }
        }

        if (@files) {
            say q[];

            P->sys->system( $upx, '--best', @files ) or 1;

            for my $file (@files) {
                P->file->copy( $file, $upx_cache_dir . $file_md5->{$file} );
            }
        }
    }

    return;
}

sub _repack_parl ( $self, $parl_path, $zip ) {
    say 'repack parl ... ';

    my $src = P->file->read_bin($parl_path);

    my $in_len = length $src->$*;

    my $hash = P->digest->md5_hex( $src->$* );

    # find zip length
    $src->$* =~ s/(.{4})\x0APAR[.]pm\x0A\z//sm;

    my $zip_overlay_length = unpack 'N', $1;

    # cut zip overlay
    my $overlay = substr $src->$*, length( $src->$* ) - $zip_overlay_length, $zip_overlay_length, q[];

    # cut CACHE_ID, now $overlay contains only parl embedded files
    $overlay =~ s/.{40}\x{00}CACHE\z//sm;

    # repacked_exe_fh contains raw exe header, without overlay
    my $repacked_exe_fh = P->file->tempfile( suffix => $self->par_suffix );

    my $exe_header_length = length $src->$*;

    P->file->write_bin( $repacked_exe_fh, $src );

    my $parl_so_temp = P->file->tempdir;

    my $parl_so_temp_map = {};

    while (1) {
        last if $overlay !~ s/\AFILE//sm;

        my $filename_length = unpack( 'N', substr( $overlay, 0, 4, q[] ) ) - 9;

        substr $overlay, 0, 9, q[];

        my $filename = substr $overlay, 0, $filename_length, q[];

        my $content_length = unpack( 'N', substr( $overlay, 0, 4, q[] ) );

        my $content = substr $overlay, 0, $content_length, q[];

        if ( $filename =~ /[.](?:pl|pm)\z/sm ) {

            # compress perl sources
            $content = Pcore::Src::File->new(
                {   action      => 'compress',
                    path        => $filename,
                    is_realpath => 0,
                    in_buffer   => \$content,
                    filter_args => {             #
                        perl_compress => 1,
                    },
                }
            )->run->out_buffer->$*;
        }
        elsif ( $self->upx && $filename =~ /[.]$Config::Config{so}\z/sm ) {

            # store shared object to the temporary path
            my $temppath = P->file->temppath( base => $parl_so_temp, suffix => $Config::Config{so} );

            P->file->write_bin( $temppath, $content );

            # save mapping for temppath -> parl filename
            $parl_so_temp_map->{$temppath} = $filename;

            next;
        }

        # pack file back to the overlay
        print {$repacked_exe_fh} 'FILE' . pack( 'N', length($filename) + 9 ) . sprintf( '%08x', Archive::Zip::computeCRC32($content) ) . q[/] . $filename . pack( 'N', length $content ) . $content;
    }

    if ( $self->upx ) {
        $self->_compress_upx( [ keys $parl_so_temp_map->%* ] );

        P->file->find(
            $parl_so_temp,
            abs => 1,
            dir => 0,
            sub ($path) {
                my $content = P->file->read_bin($path)->$*;

                my $filename = $parl_so_temp_map->{$path};

                print {$repacked_exe_fh} 'FILE' . pack( 'N', length($filename) + 9 ) . sprintf( '%08x', Archive::Zip::computeCRC32($content) ) . q[/] . $filename . pack( 'N', length $content ) . $content;

                return;
            }
        );
    }

    # add par itself
    $zip->writeToFileHandle($repacked_exe_fh);

    # write magic strings
    print {$repacked_exe_fh} pack( 'Z40', $hash ) . qq[\x00CACHE];

    print {$repacked_exe_fh} pack( 'N', $repacked_exe_fh->tell - $exe_header_length ) . "\x0APAR.pm\x0A";

    my $out_len = $repacked_exe_fh->tell;

    say 'parl repacked: ', BOLD . GREEN . q[-] . ( reverse join q[_], ( reverse( $out_len - $in_len ) ) =~ /(\d{1,3})/smg ) . RESET . ' bytes';

    # need to close fh before copy / patch file
    $repacked_exe_fh->close;

    # patch windows exe icon
    if ($MSWIN) {

        # .ico
        # 4 layers, 16x16, 32x32, 16x16, 32x32
        # all layers 8bpp, 1-bit alpha, 256-slot palette

        print 'patch win exe icon ... ';

        require Win32::Exe;

        my $exe = Win32::Exe->new( $repacked_exe_fh->path );

        $exe->update( icon => $PROC->res->get('/data/par.ico') );

        say 'done';
    }

    return $repacked_exe_fh->path;
}

sub _error ( $self, $msg ) {
    say BOLD . GREEN . 'PAR ERROR: ' . $msg . RESET;

    exit 5;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 182, 218, 541        │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 195, 254, 286, 443   │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 308                  │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 477                  │ RegularExpressions::ProhibitCaptureWithoutTest - Capture variable used outside conditional                     │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 512                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 563, 565             │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 499, 505, 569        │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
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
