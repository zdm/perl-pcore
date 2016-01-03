package Pcore::Dist::Build::PAR::Script;

use Pcore -class;
use Pcore::Util::Text qw[format_num];
use Pcore::Util::File::Tree;
use Archive::Zip qw[];
use PAR::Filter;
use Filter::Crypto::CryptFile;
use Pcore::Src::File;
use Config;
use Term::ANSIColor qw[:constants];

has dist   => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'],       required => 1 );
has script => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Path'], required => 1 );
has release => ( is => 'ro', isa => Bool, required => 1 );
has crypt   => ( is => 'ro', isa => Bool, required => 1 );
has upx     => ( is => 'ro', isa => Bool, required => 1 );
has clean   => ( is => 'ro', isa => Bool, required => 1 );

has mod      => ( is => 'ro', isa => ArrayRef, required => 1 );
has resource => ( is => 'ro', isa => ArrayRef, required => 1 );
has shlib    => ( is => 'ro', isa => ArrayRef, required => 1 );

has tree => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::File::Tree'], init_arg => undef );
has par_suffix   => ( is => 'lazy', isa => Str, init_arg => undef );
has exe_filename => ( is => 'lazy', isa => Str, init_arg => undef );

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

    push @attrs, 'x64' if $Config{archname} =~ /x64|x86_64/sm;

    return $filename . q[-] . join( q[-], @attrs ) . $self->par_suffix;
}

sub run ($self) {
    say BOLD . GREEN . qq[\nbuild] . ( $self->crypt ? ' crypted' : BOLD . RED . q[ not crypted] . BOLD . GREEN ) . qq[ "@{[$self->exe_filename]}" for $Config{archname}] . RESET;

    # add main script
    $self->_add_perl_source( $self->script->realpath->to_string, 'script/main.pl' );

    # add dist dist.perl
    $self->tree->add_file( 'share/dist.perl', $self->dist->share_dir . '/dist.perl' );

    # add dist build.perl
    $self->tree->add_file( 'share/build.perl', $self->dist->create_build_info );

    # add Pcore dist.perl
    $self->tree->add_file( 'lib/auto/share/dist/Pcore/dist.perl', $ENV->res->get_lib('pcore') . 'dist.perl' );

    # add Pcore build.perl
    $self->tree->add_file( 'lib/auto/share/dist/Pcore/build.perl', $ENV->pcore->create_build_info );

    # add META.yml
    $self->tree->add_file( 'META.yml', P->data->to_yaml( { par => { clean => 1 } } ) ) if $self->clean;

    # add shlib
    $self->_add_shlib;

    # add resources
    $self->_add_resources;

    # add modules
    print 'adding modules ... ';
    $self->_add_modules;
    say 'done';

    my $temp = $self->tree->write_to_temp;

    # compress so with upx
    if ( $self->upx ) {
        my @compress_upx;

        P->file->find(
            $temp->path,
            dir => 0,
            sub ($path) {

                # compress with upx
                if ( $path =~ /\Q$Config{so}\E\z/sm ) {
                    push @compress_upx, $path->realpath;
                }

                return;
            }
        );

        $self->_compress_upx( \@compress_upx ) if @compress_upx;
    }

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

    my $repacked_fh = $self->_repack_parl( $parl_path, $zip );

    my $target_exe = $self->dist->root . 'data/' . $self->exe_filename;

    P->file->move( $repacked_fh->path, $target_exe );

    P->file->chmod( 'r-x------', $target_exe );

    say 'final binary size: ' . BOLD . GREEN . format_num( -s $target_exe ) . RESET . ' bytes';

    return;
}

sub _add_shlib ($self) {
    for my $shlib ( $self->shlib->@* ) {
        my $found;

        if ( -f $shlib ) {
            $found = $shlib;
        }
        else {
            # find in the $ENV{PATH}, @INC
            for my $path ( split( /$Config{path_sep}/sm, $ENV{PATH} ), grep { !ref } @INC ) {
                if ( -f "$path/$shlib" ) {
                    $found = "$path/$shlib";

                    last;
                }
            }
        }

        if ($found) {
            my $filename = P->path($shlib)->filename;

            say qq[shared lib added: "$filename"];

            $self->tree->add_file( "shlib/$Config{archname}/$filename", $found );
        }
        else {
            $self->_error(qq[shared object wasn't found: "$shlib"]);
        }
    }

    return;
}

sub _add_resources ($self) {
    for my $res ( $self->resource->@* ) {
        my $path = $ENV->res->get($res);

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

sub _add_modules ($self) {

    # add .pl, .pm
    for my $module ( grep {/[.](?:pl|pm)\z/sm} $self->mod->@* ) {
        my $found = $self->_add_module($module);

        $self->_error(qq[required module wasn't found: "$module"]) if !$found;
    }

    # add .pc (part of some Win32API modules)
    for my $module ( grep {/[.](?:pc)\z/sm} $self->mod->@* ) {
        my $found;

        for my $inc ( grep { !ref } @INC ) {
            if ( -f "$inc/$module" ) {
                $found = 1;

                $self->tree->add_file( "$Config{version}/$Config{archname}/$module", "$inc/$module" );

                last;
            }
        }

        $self->_error(qq[required module wasn't found: "$module"]) if !$found;
    }

    return;
}

sub _add_module ( $self, $module ) {
    $module = P->perl->module( $module, $self->dist->root . 'lib/' );

    # module wasn't found
    return if !$module;

    my $target;

    if ( my $auto_deps = $module->auto_deps ) {

        # module have auto deps
        $target = $Config{version} . q[/] . $Config{archname} . q[/];

        for my $deps ( keys $auto_deps->%* ) {
            $self->tree->add_file( $target . $deps, $auto_deps->{$deps} );
        }
    }
    else {
        $target = 'lib/';
    }

    # add .pm to the files tree
    $self->_add_perl_source( $module->path, $target . $module->name, $module->is_installed, $module->name );

    return 1;
}

sub _add_perl_source ( $self, $source, $target, $is_installed = 0, $module = undef ) {
    my $src = P->file->read_bin($source);

    if ($module) {

        # patch content for PAR compatibility
        $src = PAR::Filter->new('PatchContent')->apply( $src, $module );

        # this is perl core or CPAN module
        if ($is_installed) {
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

    my $crypt = $self->crypt && ( !$module || $module ne 'Filter/Crypto/Decrypt.pm' );

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
    return if !$MSWIN;    # disabled for linux, upx doesn't pack anything under lnux

    my $upx;

    my $upx_cache_dir = $ENV->{PCORE_USER_DIR} . 'upx-cache/';

    if ($MSWIN) {
        $upx = $ENV->res->get('/bin/upx.exe');
    }
    else {
        $upx = $ENV->res->get('/bin/upx_x64');
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

                # change permissions, so upx can overwrite file
                # following will remove READ-ONLY attribute under windows
                chmod 0777, $file or 1;
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
        elsif ( $self->upx && $filename =~ /[.]$Config{so}\z/sm ) {

            # store shared object to the temporary path
            my $temppath = P->file->temppath( base => $parl_so_temp, suffix => $Config{so} );

            P->file->write_bin( $temppath, $content );

            # save mapping for temppath -> parl filename
            $parl_so_temp_map->{$temppath} = $filename;

            # will be compressed and added later
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

    say 'parl repacked: ', BOLD . GREEN . format_num( $out_len - $in_len ) . RESET . ' bytes';

    # need to close fh before copy / patch file
    $repacked_exe_fh->close;

    # patch windows exe icon
    if ($MSWIN) {

        # .ico
        # 4 layers, 16x16, 32x32, 16x16, 32x32
        # all layers 8bpp, 1-bit alpha, 256-slot palette

        print 'patch win exe icon ... ';

        state $init = !!require Win32::Exe;

        my $exe = Win32::Exe->new( $repacked_exe_fh->path );

        $exe->update( icon => $ENV->res->get('/data/par.ico') );

        say 'done';
    }

    return $repacked_exe_fh;
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
## │    3 │ 240, 494             │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 254                  │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 391                  │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 429                  │ RegularExpressions::ProhibitCaptureWithoutTest - Capture variable used outside conditional                     │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 464                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 516, 518             │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 451, 457             │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
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
