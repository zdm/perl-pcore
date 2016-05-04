package Pcore::Dist::Build::PAR::Script;

use Pcore -class, -ansi;
use Pcore::Util::Text qw[format_num];
use Pcore::Util::File::Tree;
use Archive::Zip qw[];
use PAR::Filter;
use Filter::Crypto::CryptFile;
use Pcore::Src::File;
use Config;

has dist   => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'],       required => 1 );
has script => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Path'], required => 1 );
has release => ( is => 'ro', isa => Bool,     required => 1 );
has crypt   => ( is => 'ro', isa => Bool,     required => 1 );
has upx     => ( is => 'ro', isa => Bool,     required => 1 );
has clean   => ( is => 'ro', isa => Bool,     required => 1 );
has mod     => ( is => 'ro', isa => HashRef,  required => 1 );
has shlib   => ( is => 'ro', isa => ArrayRef, required => 1 );

has tree => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::File::Tree'], init_arg => undef );
has par_suffix   => ( is => 'lazy', isa => Str,     init_arg => undef );
has exe_filename => ( is => 'lazy', isa => Str,     init_arg => undef );
has main_mod     => ( is => 'lazy', isa => HashRef, default  => sub { {} }, init_arg => undef );    # main modules, found during deps processing
has share        => ( is => 'ro',   isa => HashRef, default  => sub { {} }, init_arg => undef );

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
        if ( $self->dist->id->{bookmark} ) {
            push @attrs, $self->dist->id->{bookmark};
        }
        else {
            push @attrs, $self->dist->id->{branch};
        }
    }

    push @attrs, 'x64' if $Config{archname} =~ /x64|x86_64/sm;

    return $filename . q[-] . join( q[-], @attrs ) . $self->par_suffix;
}

sub run ($self) {
    say qq[\nBuilding ] . ( $self->crypt ? BLACK ON_GREEN . ' crypted ' : BOLD WHITE ON_RED . q[ not crypted ] ) . RESET . qq[ "@{[$self->exe_filename]}" for $Config{archname}$LF];

    # add main script
    $self->_add_perl_source( $self->script->realpath->to_string, 'script/main.pl' );

    # add META.yml
    $self->tree->add_file( 'META.yml', P->data->to_yaml( { par => { clean => 1 } } ) ) if $self->clean;

    # add modules
    print 'adding modules ... ';

    $self->_add_modules;

    say 'done';

    # process found main modules
    $self->_process_main_modules;

    # add shares
    $self->_add_share;

    # add shlib
    $self->_add_shlib;

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

    say 'final binary size: ' . BLACK ON_GREEN . q[ ] . format_num( -s $target_exe ) . q[ ] . RESET . ' bytes';

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

            say qq[shlib added: "$filename"];

            $self->tree->add_file( "shlib/$Config{archname}/$filename", $found );
        }
        else {
            $self->_error(qq[shlib wasn't found: "$shlib"]);
        }
    }

    return;
}

sub _add_share ($self) {
    for my $res ( keys $self->share->%* ) {
        my $path = $ENV->share->get($res);

        if ( !$path ) {
            $self->_error(qq[required share "$res" wasn't found]);
        }
        else {
            say qq[share added: "$res"];

            $self->tree->add_file( 'share/' . $res, $path );
        }
    }

    return;
}

sub _add_modules ($self) {

    # add .pl, .pm
    for my $module ( grep {/[.](?:pl|pm)\z/sm} keys $self->mod->%* ) {
        my $found = $self->_add_module($module);

        $self->_error(qq[required module wasn't found: "$module"]) if !$found;
    }

    # add .pc (part of some Win32API modules)
    for my $module ( grep {/[.](?:pc)\z/sm} keys $self->mod->%* ) {
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
        $target = "$Config{version}/$Config{archname}/";

        for my $deps ( keys $auto_deps->%* ) {
            $self->tree->add_file( $target . $deps, $auto_deps->{$deps} );
        }
    }
    else {
        $target = 'lib/';
    }

    # add .pm to the files tree
    $self->_add_perl_source( $module->path, $target . $module->name, $module->is_cpan_module, $module->name );

    return 1;
}

sub _add_perl_source ( $self, $source, $target, $is_cpan_module = 0, $module = undef ) {
    my $src = P->file->read_bin($source);

    if ($module) {

        # detect pcore dist main module
        if ( $src->$* =~ /^use Pcore.+-dist.*;/m ) {    ## no critic qw[RegularExpressions::RequireDotMatchAnything]
            $self->main_mod->{$module} = [ $source, $target ];
        }

        # patch content for PAR compatibility
        $src = PAR::Filter->new('PatchContent')->apply( $src, $module );
    }

    $src = Pcore::Src::File->new(
        {   action      => 'compress',
            path        => $target,
            is_realpath => 0,
            in_buffer   => $src,
            filter_args => {
                perl_compress_keep_ln => 1,
                perl_strip_comment    => 1,
                perl_strip_pod        => 1,
            },
        }
    )->run->out_buffer;

    # crypt sources, do not crypt CPAN modules
    if ( !$is_cpan_module && $self->crypt && ( !$module || $module ne 'Filter/Crypto/Decrypt.pm' ) ) {
        my $crypt = 1;

        # do not crypt modules, that belongs to the CPAN distribution
        if ( !$is_cpan_module && ( my $dist = Pcore::Dist->new( P->path($source)->dirname ) ) ) {
            $crypt = 0 if $dist->cfg->{cpan};
        }

        if ($crypt) {
            open my $crypt_in_fh, '<', $src or die;

            open my $crypt_out_fh, '+>', \my $crypted_src or die;

            Filter::Crypto::CryptFile::crypt_file( $crypt_in_fh, $crypt_out_fh, Filter::Crypto::CryptFile::CRYPT_MODE_ENCRYPTED() );

            close $crypt_in_fh or die;

            close $crypt_out_fh or die;

            $src = \$crypted_src;
        }
    }

    $self->tree->add_file( $target, $src );

    return;
}

sub _process_main_modules ($self) {

    # add Pcore dist
    $self->_add_dist( $ENV->pcore );

    for my $main_mod ( keys $self->main_mod->%* ) {
        next if $main_mod eq 'Pcore.pm' or $main_mod eq $self->dist->module->name;

        my $dist = Pcore::Dist->new($main_mod);

        $self->_error(qq[corrupted main module: "$main_mod"]) if !$dist;

        $self->_add_dist($dist);
    }

    # add current dist, should be added last to preserve share libs order
    $self->_add_dist( $self->dist );

    return;
}

sub _add_dist ( $self, $dist ) {
    if ( $dist->name eq $self->dist->name ) {

        # add main dist dist.perl
        $self->tree->add_file( 'share/dist.perl', $dist->share_dir . '/dist.perl' );

        # add main dist dist-id.json
        $self->tree->add_file( 'share/dist-id.json', P->data->to_json( $dist->id, readable => 1 ) );
    }
    else {

        # add dist.perl
        $self->tree->add_file( "lib/auto/share/dist/@{[ $dist->name ]}/dist.perl", $dist->share_dir . '/dist.perl' );

        # add dist-id.json
        $self->tree->add_file( "lib/auto/share/dist/@{[ $dist->name ]}/dist-id.json", P->data->to_json( $dist->id, readable => 1 ) );
    }

    # register dist share in order to find them later via $ENV->share->get interface
    $ENV->register_dist($dist);

    # process dist modules shares
    if ( $dist->cfg->{mod_share} ) {

        # register shares to add later
        for my $mod ( grep { exists $self->mod->{$_} } keys $dist->cfg->{mod_share}->%* ) {
            $self->share->@{ $dist->cfg->{mod_share}->{$mod}->@* } = ();
        }
    }

    say 'dist added: ' . $dist->name;

    return;
}

sub _compress_upx ( $self, $path ) {
    return if !$MSWIN;    # disabled for linux, upx doesn't pack anything under lnux

    my $upx;

    my $upx_cache_dir = $ENV->{PCORE_USER_DIR} . 'upx-cache/';

    if ($MSWIN) {
        $upx = $ENV->share->get('/bin/upx.exe');
    }
    else {
        $upx = $ENV->share->get('/bin/upx_x64');
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

            my $cmd = q[];

            for my $file (@files) {
                if ( length qq[$cmd "$file"] > 8191 ) {
                    P->pm->run_proc($cmd) or 1;

                    $cmd = qq[$upx --best "$file"];
                }
                else {
                    $cmd ||= qq[$upx --best];

                    $cmd .= qq[ "$file"];
                }
            }

            P->pm->run_proc($cmd) or 1 if $cmd;

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

    my $file_section = {};

    while (1) {
        last if $overlay !~ s/\AFILE//sm;

        my $filename_length = unpack( 'N', substr( $overlay, 0, 4, q[] ) ) - 9;

        substr $overlay, 0, 9, q[];

        my $filename = substr $overlay, 0, $filename_length, q[];

        my $content_length = unpack( 'N', substr( $overlay, 0, 4, q[] ) );

        my $content = substr $overlay, 0, $content_length, q[];

        if ( $filename =~ /[.](?:pl|pm)\z/sm ) {

            # compress perl sources
            $file_section->{$filename} = Pcore::Src::File->new(
                {   action      => 'compress',
                    path        => $filename,
                    is_realpath => 0,
                    in_buffer   => \$content,
                    filter_args => {             #
                        perl_compress         => 1,
                        perl_compress_keep_ln => 0,
                    },
                }
            )->run->out_buffer;
        }
        elsif ( $self->upx && $filename =~ /[.]$Config{so}\z/sm ) {

            # store shared object to the temporary path
            my $temppath = P->file->temppath( base => $parl_so_temp, suffix => $Config{so} );

            P->file->write_bin( $temppath, $content );

            $file_section->{$filename} = $temppath->path;
        }
        else {
            $file_section->{$filename} = \$content;
        }
    }

    if ( $self->upx ) {
        $self->_compress_upx( [ grep { !ref } values $file_section->%* ] );
    }

    # pack files sections
    for my $filename ( sort keys $file_section->%* ) {
        my $content = ref $file_section->{$filename} ? $file_section->{$filename} : P->file->read_bin( $file_section->{$filename} );

        print {$repacked_exe_fh} 'FILE' . pack( 'N', length($filename) + 9 ) . sprintf( '%08x', Archive::Zip::computeCRC32( $content->$* ) ) . q[/] . $filename . pack( 'N', length $content->$* ) . $content->$*;
    }

    # add par itself
    $zip->writeToFileHandle($repacked_exe_fh);

    # write magic strings
    print {$repacked_exe_fh} pack( 'Z40', $hash ) . qq[\x00CACHE];

    print {$repacked_exe_fh} pack( 'N', $repacked_exe_fh->tell - $exe_header_length ) . "\x0APAR.pm\x0A";

    my $out_len = $repacked_exe_fh->tell;

    say 'parl repacked: ', BLACK ON_GREEN . q[ ] . format_num( $out_len - $in_len ) . q[ ] . RESET . ' bytes';

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

        $exe->update( icon => $ENV->share->get('/data/par.ico') );

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
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 179, 198, 205, 237,  | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |      | 312, 353, 502, 506   |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 251                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 387, 405             | ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 440                  | RegularExpressions::ProhibitCaptureWithoutTest - Capture variable used outside conditional                     |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 516, 518             | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 462, 468             | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
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
