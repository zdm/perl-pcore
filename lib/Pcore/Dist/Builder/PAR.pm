package Pcore::Dist::Builder::PAR;

use Pcore qw[-class];
use Config qw[];
use Archive::Zip qw[];
use Module::Metadata qw[];
use PAR::Filter;
use Pcore::Src::File;
use Term::ANSIColor qw[:constants];

with qw[Pcore::Dist::Command];

has _pardeps      => ( is => 'lazy', isa => HashRef, init_arg => undef );
has dist_version  => ( is => 'ro',   isa => Str,     init_arg => undef );
has build_version => ( is => 'ro',   isa => Str,     init_arg => undef );

no Pcore;

our $PAR_CFG = P->cfg->load( $P->{SHARE_DIR} . 'pcore.perl' );

sub _build__pardeps ($self) {
    if ( -f 'data/.pardeps.cbor' ) {
        return P->cfg->load('data/.pardeps.cbor');
    }
    else {
        say q["data/.pardeps.cbor" not exists.];

        say q[Run source scripts with ---scan-deps argument.];

        exit 1;
    }
}

sub _build_dist_version ($self) {
    my $info = Module::Metadata->new_from_file( 'lib/' . $self->builder->dist->main_module_rel_path );

    return $info->version;
}

sub _build_build_version ($self) {
    return P->date->now_utc->strftime('%Y%m%d%H%M%S');
}

sub build_par {
    my $self = shift;
    my %args = (
        release => 0,
        crypt   => undef,
        noupx   => undef,
        clean   => undef,
        @_,
    );

    # read PAR profile
    my $profile = P->cfg->load('share/dist.perl')->{dist}->{par};

    if ( !$profile || ref $profile ne 'HASH' ) {
        say q[par profile wasn't found.];

        exit;
    }

    # build scripts
    for my $script ( sort keys $profile->%* ) {
        $profile->{$script}->{release} = $args{release};

        $profile->{$script}->{crypt} = $args{crypt} if defined $args{crypt};

        $profile->{$script}->{noupx} = $args{noupx} if defined $args{noupx};

        $profile->{$script}->{clean} = $args{clean} if defined $args{clean};

        $self->_build_script( $script, $profile->{$script} );
    }

    return;
}

sub _build_script {
    my $self    = shift;
    my $script  = P->path(shift);
    my $profile = shift;

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
    P->file->copy( $P->{SHARE_DIR}, $par_dir . 'lib/auto/share/dist/Pcore/' );

    # add current dist share dir
    P->file->copy( './share/', $par_dir . 'lib/auto/share/dist/' . $self->builder->dist->cfg->{dist}->{name} . q[/] );

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

sub _add_pkg {
    my $self    = shift;
    my $pkg     = shift;
    my $par_dir = shift;
    my $profile = shift;

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
        my $pkg_inline_so_path = $P->{INLINE_DIR} . q[lib/auto/] . $pkg_path->dirname . $pkg_path->filename_base . q[/] . $pkg_path->filename_base . q[.];

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

            $self->_copy_file( $P->{INLINE_DIR} . $inline_config_name, $inline_config_target_path ) if !-f $inline_config_target_path;
        }

        $self->_add_perl_source( $inc_path . q[/] . $pkg, $par_dir . $package_target_path . $pkg, $profile, $pkg, $found->[1] );
    }

    return $found;
}

# TODO patch pod with version info:
# pcore version, changeset id
# dist version, changeset id
# build date, UTC
sub _add_perl_source {
    my $self             = shift;
    my $from             = P->path(shift);
    my $to               = P->path(shift);
    my $profile          = shift;
    my $pkg              = shift;            # main script, if not specified
    my $is_public_module = shift;

    P->file->mkpath( $to->dirname ) if !-d $to->dirname;

    my $src = P->file->read_bin($from);

    # process perl core and CPAN modules
    if ($pkg) {

        # patch content for PAR compatibility
        $src = PAR::Filter->new('PatchContent')->apply( $src, $pkg );

        # this is perl core or CPAN module
        if ($is_public_module) {
            if ( $profile->{release} ) {
                $src = Pcore::Src::File->new(
                    {   action      => 'compress',
                        path        => $to,
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
                        path        => $to,
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

            P->file->write_bin( $to, $src );

            return;
        }
    }

    # extract CLI pod
    # for main.pl - pod always extracted
    # for particular module - extracted only if module used as pcore CLI interface
    if ( !$pkg || $src->$* =~ /^use\s+P[^;]+-cli[^;]+;/sm ) {
        require Pod::Select;

        Pod::Select::podselect( { -output => $to->dirname . $to->filename_base . q[.pod] }, $from->to_string );
    }

    my $crypt = $profile->{crypt} && ( !$pkg || $pkg ne 'Filter/Crypto/Decrypt.pm' );

    # we don't compress sources for devel build, preserving line numbers
    if ( !$profile->{release} ) {
        $src = Pcore::Src::File->new(
            {   action      => 'compress',
                path        => $to,
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
        if ($crypt) {    # for crypted release - only strip sources without preserving line numbers, Filter::Crypto::Decrypt isn't work with compressed sources
            $src = Pcore::Src::File->new(
                {   action      => 'compress',
                    path        => $to,
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
        else {    # for not crypted release - compress all sources
            $src = Pcore::Src::File->new(
                {   action      => 'compress',
                    path        => $to,
                    is_realpath => 0,
                    in_buffer   => $src,
                    filter_args => {             #
                        perl_compress => 1,
                    },
                }
            )->run->out_buffer;
        }
    }

    P->file->write_bin( $to, $src );

    # crypt sources, if nedeed
    if ($crypt) {
        require Filter::Crypto::CryptFile;

        Filter::Crypto::CryptFile::crypt_file( $to->to_string, Filter::Crypto::CryptFile::CRYPT_MODE_ENCRYPTED() );
    }

    return;
}

sub _copy_file {
    my $self = shift;
    my $from = shift;
    my $to   = shift;

    my $to_path = P->path($to);

    P->file->mkpath( $to_path->dirname ) if !-d $to_path->dirname;

    P->file->copy( $from, $to );

    if ($MSWIN) {
        require Win32::File;

        Win32::File::SetAttributes( $to, Win32::File::NORMAL() ) or die;
    }
    else {
        P->file->chmod( 'rw-------', $to );
    }

    return;
}

sub _upx {
    my $self = shift;
    my $path = P->path(shift);

    my $upx;

    if ($MSWIN) {
        $upx = P->res->get_local('upx.exe');
    }
    else {
        $upx = P->res->get_local('upx_x64');
    }

    P->capture->sys( $upx, '--best', $path ) if $upx;

    return;
}

sub _repack_par {
    my $self     = shift;
    my $in_path  = shift;
    my $out_path = shift;
    my $profile  = shift;
    my $zip      = shift;

    print 'repack parl ... ';

    my $src = P->file->read_bin($in_path);

    my $in_len = length $src->$*;

    my $hash = P->digest->md5_hex( $src->$* );

    $src->$* =~ s/(.{4})\x0APAR[.]pm\x0A\z//sm;

    my $overlay_length = unpack 'N', $1;

    my $overlay = substr $src->$*, length( $src->$* ) - $overlay_length, $overlay_length, q[];

    $overlay =~ s/.{40}\x{00}CACHE\z//sm;

    my $fh = P->file->tempfile( binmode => ':raw' );

    # print exe header
    print {$fh} $src->$*;

    my $exe_header_length = $fh->tell;

    while (1) {
        last if $overlay !~ s/\AFILE//sm;

        my $filename_length = unpack( 'N', substr( $overlay, 0, 4, q[] ) ) - 9;

        substr $overlay, 0, 9, q[];

        my $filename = substr $overlay, 0, $filename_length, q[];

        my $content_length = unpack( 'N', substr( $overlay, 0, 4, q[] ) );

        my $content = substr $overlay, 0, $content_length, q[];

        if ( $filename =~ /[.](?:pl|pm)\z/sm ) {
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
        elsif ( !$profile->{noupx} && $filename =~ /[.]$Config::Config{dlext}\z/sm ) {
            state $i;

            my $temp_path = $PROC->{TEMP_DIR} . 'parl_so_' . ++$i;

            P->file->write_bin( $temp_path, $content );

            $self->_upx($temp_path);

            $content = P->file->read_bin($temp_path)->$*;
        }

        # pack file back to overlay
        print {$fh} 'FILE' . pack( 'N', length($filename) + 9 ) . sprintf( '%08x', Archive::Zip::computeCRC32($content) ) . q[/] . $filename . pack( 'N', length $content ) . $content;
    }

    # add par itself
    $zip->writeToFileHandle($fh);

    # write magic strings
    print {$fh} pack( 'Z40', $hash ) . qq[\x00CACHE];

    print {$fh} pack( 'N', $fh->tell - $exe_header_length ) . "\x0APAR.pm\x0A";

    my $out_len = $fh->tell;

    say BOLD . GREEN . q[-] . ( reverse join q[_], ( reverse( $out_len - $in_len ) ) =~ /(\d{1,3})/smg ) . RESET . ' bytes';

    # need to close fh before copy / patch file
    $fh->close;

    # patch windows exe icon
    if ($MSWIN) {

        # .ico
        # 4 layers, 16x16, 32x32, 16x16, 32x32
        # all layers 8bpp, 1-bit alpha, 256-slot palette

        print 'patch win exe icon ... ';

        require Win32::Exe;

        my $exe = Win32::Exe->new( $fh->path );

        $exe->update( icon => P->res->get_local('par.ico') );

        say 'done';
    }

    P->file->copy( $fh->path, $out_path );

    P->file->chmod( 'r-x------', $out_path );

    say 'final binary size: ' . BOLD . GREEN . ( reverse join q[_], ( reverse -s $out_path ) =~ /(\d{1,3})/smg ) . RESET . ' bytes';

    return;
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
## │    3 │ 64, 113, 128         │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 79                   │ Subroutines::ProhibitExcessComplexity - Subroutine "_build_script" with high complexity score (25)             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 142, 230, 252, 571   │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 462                  │ RegularExpressions::ProhibitCaptureWithoutTest - Capture variable used outside conditional                     │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 167, 489             │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 520, 522             │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 478, 484, 526        │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
