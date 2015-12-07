package Pcore::Util::File;

use Pcore;
use Fcntl qw[:DEFAULT];
use Cwd qw[];    ## no critic qw[Modules::ProhibitEvilModules]

sub cat_path ( $self, @ ) {
    return P->path( join q[/], splice @_, 1 );
}

# return cwd, symlinks are resolved
sub cwd ($self) {
    return P->path( Cwd::realpath(q[.]), is_dir => 1 );
}

sub chdir ( $self, $path ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    if ( defined wantarray ) {
        my $cwd = $self->cwd->to_string;

        return unless chdir $path;

        require Pcore::Util::File::ChdirGuard;

        return Pcore::Util::File::ChdirGuard->new( { dir => $cwd } )->scope_guard;
    }
    elsif ( chdir $path ) {
        return;
    }
    else {
        die qq[Can't chdir to "$path"];
    }
}

# change umask and return old umask
sub umask ( $self, $mode ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    return '00' if $MSWIN;

    if ( defined wantarray ) {
        require Pcore::Util::File::UmaskGuard;

        return Pcore::Util::File::UmaskGuard->new( { old_umask => umask $self->calc_umask($mode) } );
    }
    else {
        return umask $self->calc_umask($mode);
    }
}

sub calc_umask ( $self, $mode, % ) {
    return unless defined $mode;

    my %args = (
        oct => 0,
        @_[ 2 .. $#_ ],
    );

    if ( $mode =~ /[^[:digit:]]/smi ) {
        state $mode_cache = {};

        if ( !exists $mode_cache->{$mode} ) {
            my $mode_val = 0b111_111_111;    # all perms are disabled by default

            my @mode = map {lc} split //sm, $mode;

            # user
            $mode_val &= 0b011_111_111 if defined $mode[0] && $mode[0] eq q[r];
            $mode_val &= 0b101_111_111 if defined $mode[1] && $mode[1] eq q[w];
            $mode_val &= 0b110_111_111 if defined $mode[2] && $mode[2] eq q[x];

            # group
            $mode_val &= 0b111_011_111 if defined $mode[3] && $mode[3] eq q[r];
            $mode_val &= 0b111_101_111 if defined $mode[4] && $mode[4] eq q[w];
            $mode_val &= 0b111_110_111 if defined $mode[5] && $mode[5] eq q[x];

            # other
            $mode_val &= 0b111_111_011 if defined $mode[6] && $mode[6] eq q[r];
            $mode_val &= 0b111_111_101 if defined $mode[7] && $mode[7] eq q[w];
            $mode_val &= 0b111_111_110 if defined $mode[8] && $mode[8] eq q[x];

            $mode_cache->{$mode} = $mode_val;
        }

        $mode = $mode_cache->{$mode};
    }
    else {
        $mode = oct $mode if substr( $mode, 0, 1 ) eq '0';
    }

    return $args{oct} ? sprintf '0%o', $mode : $mode;
}

# mkdir with chmod support
sub mkdir ( $self, $path, $mode = undef ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    if ( defined wantarray ) {
        if ( defined $mode ) {
            return mkdir $path, $self->calc_chmod($mode);
        }
        else {
            return mkdir $path;
        }
    }
    else {
        if ( defined $mode ) {
            mkdir $path, $self->calc_chmod($mode) or die qq[Can't mkdir "$path". $!];
        }
        else {
            mkdir $path or die qq[Can't mkdir "$path". $!];
        }

        return;
    }
}

sub chmod ( $self, $mode, @path ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    if ( defined wantarray ) {
        return chmod $self->calc_chmod($mode), @path;
    }
    else {
        return chmod( $self->calc_chmod($mode), @path ) || die qq[$! during chmod $mode, ] . join q[, ], @path;
    }
}

sub calc_chmod ( $self, $mode, % ) {
    return unless defined $mode;

    my %args = (
        oct => 0,
        @_[ 2 .. $#_ ],
    );

    if ( $mode =~ /[^[:digit:]]/smi ) {
        state $mode_cache = {};

        if ( !exists $mode_cache->{$mode} ) {
            my $mode_val = 0;    # all perms are disabled by default

            my @mode = map {lc} split //sm, $mode;

            # user
            $mode_val |= 0b100_000_000 if defined $mode[0] && $mode[0] eq q[r];
            $mode_val |= 0b010_000_000 if defined $mode[1] && $mode[1] eq q[w];
            $mode_val |= 0b001_000_000 if defined $mode[2] && $mode[2] eq q[x];

            # group
            $mode_val |= 0b000_100_000 if defined $mode[3] && $mode[3] eq q[r];
            $mode_val |= 0b000_010_000 if defined $mode[4] && $mode[4] eq q[w];
            $mode_val |= 0b000_001_000 if defined $mode[5] && $mode[5] eq q[x];

            # other
            $mode_val |= 0b000_000_100 if defined $mode[6] && $mode[6] eq q[r];
            $mode_val |= 0b000_000_010 if defined $mode[7] && $mode[7] eq q[w];
            $mode_val |= 0b000_000_001 if defined $mode[8] && $mode[8] eq q[x];

            $mode_cache->{$mode} = $mode_val;
        }

        $mode = $mode_cache->{$mode};
    }
    else {
        $mode = oct $mode if substr( $mode, 0, 1 ) eq '0';
    }

    return $args{oct} ? sprintf '0%o', $mode : $mode;
}

# READ / WRITE
sub read_bin ( $self, $path, % ) {
    my %args = (
        cb       => undef,
        buf_size => 1_048_576,
        @_[ 2 .. $#_ ],
    );

    my $fh = $self->get_fh( $path, O_RDONLY, crlf => 0 );

    my $tail = q[];

  READ:
    my $bytes = read $fh, my $buf, $args{buf_size};

    die qq[Couldn't read file "$path": $!] if !defined $bytes;

    if ( $args{cb} ) {
        if ($bytes) {
            return if !$args{cb}->( \$buf );

            goto READ;
        }
        else {
            $args{cb}->(undef);

            return;
        }
    }
    else {
        if ($bytes) {
            $tail .= $buf;

            goto READ;
        }
        else {
            return \$tail;
        }
    }
}

sub read_text ( $self, $path, % ) {
    my %args = (
        crlf     => 1,                    # undef - auto, 1 - on, 0 - off (for binary files)
        binmode  => ':encoding(UTF-8)',
        cb       => undef,
        buf_size => 1_048_576,
        @_[ 2 .. $#_ ],
    );

    my $fh = $self->get_fh( $path, O_RDONLY, crlf => $args{crlf}, binmode => $args{binmode} );

    my $tail = q[];

  READ:
    my $bytes = read $fh, my $buf, $args{buf_size};

    die qq[Couldn't read file "$path": $!] if !defined $bytes;

    if ( $args{cb} ) {
        if ($bytes) {
            return if !$args{cb}->( \$buf );

            goto READ;
        }
        else {
            $args{cb}->(undef);

            return;
        }
    }
    else {
        if ($bytes) {
            $tail .= $buf;

            goto READ;
        }
        else {
            return \$tail;
        }
    }
}

sub read_lines ( $self, $path, % ) {
    my %args = (
        crlf        => 1,                    # undef - auto, 1 - on, 0 - off (for binary files)
        binmode     => ':encoding(UTF-8)',
        cb          => undef,
        buf_size    => 1_048_576,
        empty_lines => 0,                    # only for array_ref mode, don't skip empty lines
        @_[ 2 .. $#_ ],
    );

    my $fh = $self->get_fh( $path, O_RDONLY, crlf => $args{crlf}, binmode => $args{binmode} );

    my $tail = q[];

  READ:
    my $bytes = read $fh, my $buf, $args{buf_size};

    die qq[Couldn't read file "$path": $!] if !defined $bytes;

    if ( $args{cb} ) {
        if ($bytes) {
            if ( index( $buf, qq[\n] ) == -1 ) {    # buf doesn't contains strings
                $tail .= $buf;
            }
            else {                                  # buf contains strings
                $buf = $tail . $buf;

                if ( $args{empty_lines} ) {
                    my $array_ref = [ split /\n/sm, $buf, -1 ];

                    $tail = pop $array_ref->@*;

                    return if !$args{cb}->($array_ref);
                }
                else {
                    my $array_ref = [ split /\n+/sm, $buf ];

                    # remove leading q[], preserved by split
                    shift $array_ref->@* if defined $array_ref->[0] && $array_ref->[0] eq q[];

                    if ( substr( $buf, -1, 1 ) ne qq[\n] ) {
                        $tail = pop $array_ref->@*;
                    }
                    else {
                        $tail = q[];
                    }

                    if ( $array_ref->@* ) {
                        return if !$args{cb}->($array_ref);
                    }
                }
            }

            goto READ;
        }
        else {
            if ( $tail ne q[] ) {
                return if !$args{cb}->( [$tail] );
            }

            $args{cb}->(undef);

            return;
        }
    }
    else {
        if ($bytes) {
            $tail .= $buf;

            goto READ;
        }
        else {
            if ( $args{empty_lines} ) {
                my $array_ref = [ split /\n/sm, $tail, -1 ];

                # remove trailing q[], preserved by split
                pop $array_ref->@* if defined $array_ref->[-1] && $array_ref->[-1] eq q[];

                return $array_ref;
            }
            else {
                my $array_ref = [ split /\n+/sm, $tail ];

                # remove leading q[], preserved by split
                shift $array_ref->@* if defined $array_ref->[0] && $array_ref->[0] eq q[];

                return $array_ref;
            }
        }
    }
}

sub write_bin {
    my $self = shift;
    my $path = shift;
    my %args = (
        mode      => 'rw-------',
        umask     => undef,
        autoflush => 1,
        ( ref $_[0] eq 'HASH' ? %{ shift @_ } : () ),
    );

    $self->_write_to_fh( $self->get_fh( $path, O_WRONLY | O_CREAT | O_TRUNC, %args, crlf => 0 ), @_ );

    return;
}

sub append_bin {
    my $self = shift;
    my $path = shift;
    my %args = (
        mode      => 'rw-------',
        umask     => undef,
        autoflush => 1,
        ( ref $_[0] eq 'HASH' ? %{ shift @_ } : () ),
    );

    $self->_write_to_fh( $self->get_fh( $path, O_WRONLY | O_CREAT | O_APPEND, %args, crlf => 0 ), @_ );

    return;
}

sub write_text {
    my $self = shift;
    my $path = shift;
    my %args = (
        crlf      => undef,                # undef - auto, 1 - on, 0 - off (for binary files)
        binmode   => ':encoding(UTF-8)',
        autoflush => 1,
        mode      => 'rw-------',
        umask     => undef,
        ( ref $_[0] eq 'HASH' ? %{ shift @_ } : () ),
    );

    $self->_write_to_fh( $self->get_fh( $path, O_WRONLY | O_CREAT | O_TRUNC, %args ), @_ );

    return;
}

sub append_text {
    my $self = shift;
    my $path = shift;
    my %args = (
        crlf      => undef,                # undef - auto, 1 - on, 0 - off (for binary files)
        binmode   => ':encoding(UTF-8)',
        autoflush => 1,
        mode      => 'rw-------',
        umask     => undef,
        ( ref $_[0] eq 'HASH' ? %{ shift @_ } : () ),
    );

    $self->_write_to_fh( $self->get_fh( $path, O_WRONLY | O_CREAT | O_APPEND, %args ), @_ );

    return;
}

sub encode_path ( $self, $path ) {
    if ($MSWIN) {
        state $enc = Encode::find_encoding($Pcore::WIN_ENC);

        return $enc->encode( $path, Encode::FB_CROAK ) if utf8::is_utf8($path);
    }

    return $path;
}

sub get_fh ( $self, $path, $mode, % ) {
    my %args = (
        mode      => 'rw-------',
        umask     => undef,
        crlf      => 0,             # undef - auto, 1 - on, 0 - off (for binary files)
        binmode   => undef,
        autoflush => 1,
        @_[ 3 .. $#_ ],
    );

    if ( P->scalar->is_glob($path) ) {
        return $path;
    }
    else {
        my $umask_guard;

        $umask_guard = $self->umask( $args{umask} ) if defined $args{umask};

        # encode filename to native OS encoding
        $path = $self->encode_path($path);

        sysopen my $fh, $path, $mode, $self->calc_chmod( $args{mode} ) or die qq[Can't open file "$path"];

        my $binmode = q[];

        $args{crlf} //= $MSWIN ? 1 : 0;

        if ( $args{crlf} ) {
            $binmode = ':crlf' if !$MSWIN;
        }
        else {
            $binmode = ':raw' if $MSWIN;
        }

        $binmode .= $args{binmode} if $args{binmode};

        binmode $fh, $binmode or die qq[Can't set binmode file "$path"] if $binmode;

        $fh->autoflush(1) if $args{autoflush};

        return $fh;
    }
}

sub _write_to_fh {
    my $self = shift;
    my $fh   = shift;

    for my $str (@_) {
        if ( ref $str eq 'ARRAY' ) {
            for my $line ( $str->@* ) {
                print {$fh} $line, qq[\n];
            }
        }
        elsif ( ref $str eq 'SCALAR' ) {
            print {$fh} $str->$*;
        }
        else {
            print {$fh} $str;
        }
    }

    return;
}

# READ DIR
sub read_dir ( $self, $path, % ) {
    my %args = (
        keep_dot  => 0,
        full_path => 0,
        @_[ 2 .. $#_ ],
    );

    opendir my $dh, $path or die qq[Can't open dir "$path"];

    my $files;

    if ( $args{keep_dot} ) {
        $files = [ readdir $dh ];
    }
    else {
        $files = [ grep { $_ ne q[.] && $_ ne q[..] } readdir $dh ];
    }

    if ( $args{full_path} ) {
        my $path = P->path( $path, is_dir => 1 );

        $files = [ map { $path . $_ } $files->@* ];
    }

    closedir $dh or die;

    return $files;
}

# TOUCH
sub touch ( $self, $path, % ) {
    my %args = (
        atime => undef,
        mtime => undef,
        mode  => q[rw-------],
        umask => undef,
        @_[ 2 .. $#_ ],
    );

    $path = $self->encode_path($path);

    if ( !-e $path ) {

        # set umask if defined
        my $umask_guard = defined $args{umask} ? $self->umask( $args{umask} ) : undef;

        sysopen my $FH, $path, Fcntl::O_WRONLY | Fcntl::O_CREAT | Fcntl::O_APPEND, $self->calc_chmod( $args{mode} ) or die qq[Can't touch file "$path"];

        close $FH or die;
    }

    # set utime
    $args{atime} //= $args{mtime} // time;
    $args{mtime} //= $args{atime};
    utime $args{atime}, $args{mtime}, $path or die;

    return;
}

# MKPATH, RMTREE, EMPTY_DIR
sub mkpath ( $self, $path, % ) {
    my %args = (
        mode  => q[rwx------],
        umask => undef,
        @_[ 2 .. $#_ ],
    );

    require File::Path;    ## no critic qw[Modules::ProhibitEvilModules]

    $args{mode} = $self->calc_chmod( $args{mode} );

    my $umask_guard = defined $args{umask} ? $self->umask( delete $args{umask} ) : delete $args{umask};

    return File::Path::make_path( "$path", \%args );
}

sub rmtree ( $self, $path, % ) {
    my %args = (
        safe      => 0,    # 0 - will attempts to alter file permission
        keep_root => 0,
        @_[ 2 .. $#_ ],
    );

    require File::Path;    ## no critic qw[Modules::ProhibitEvilModules]

    return File::Path::remove_tree( "$path", \%args );
}

sub empty_dir ( $self, $path, % ) {
    my %args = (
        safe => 0,         # 0 - will attempts to alter file permission
        @_[ 2 .. $#_ ],
        keep_root => 1,
    );

    require File::Path;    ## no critic qw[Modules::ProhibitEvilModules]

    return File::Path::remove_tree( "$path", \%args );
}

# TEMP
sub tempfile ( $self, %args ) {
    require Pcore::Util::File::TempFile;

    return Pcore::Util::File::TempFile->new(%args);
}

sub tempdir ( $self, %args ) {
    require Pcore::Util::File::TempDir;

    return Pcore::Util::File::TempDir->new( \%args );
}

sub temppath ( $self, @ ) {
    my %args = (
        base   => $PROC->{TEMP_DIR},
        suffix => q[],
        tmpl   => 'temp-' . P->sys->pid . '-XXXXXXXX',
        @_[ 1 .. $#_ ],
    );

    $args{suffix} = q[.] . $args{suffix} if defined $args{suffix} && $args{suffix} ne q[] && substr( $args{suffix}, 0, 1 ) ne q[.];

    require Pcore::Util::File::TempFile;

    P->file->mkpath( $args{base} ) if !-e $args{base};

    my $attempt = 3;

  REDO:
    die q[Can't create temporary path] if !$attempt--;

    my $filename = $args{tmpl} =~ s/X/$Pcore::Util::File::TempFile::TMPL->[rand $Pcore::Util::File::TempFile::TMPL->@*]/smger . $args{suffix};

    goto REDO if -e $args{base} . q[/] . $filename;

    return P->path( $args{base} . q[/] . $filename );
}

# COPY / MOVE FILE
sub copy ( $self, $from, $to, % ) {
    my %args = (
        glob      => undef,
        dir_mode  => q[rwxr-xr-x],
        umask     => undef,
        buf_size  => undef,
        copy_link => 0,              # if 1 - symlinks will be copied as symlinks
        rm_file   => 1,              # remove target file before copying, 0 - off, 1 - die if can't remove, 2 - return if can't remove
        rm_dir    => 1,              # remove target dir before copying, 0 - off, 1 - die if can't remove, 2 - return if can't remove
        pfs_check => 1,
        cprf      => 1,              # only if $to is dir, if $to/ is exists put $from/ content into $to/ instead of replace $to/ with $from/
        @_[ 3 .. $#_ ],
    );

    my $umask_guard = defined $args{umask} ? $self->umask( $args{umask} ) : undef;

    local $File::Copy::Recursive::DirPerms = $self->calc_chmod( $args{dir_mode}, oct => 1 );
    local $File::Copy::Recursive::CopyLink = $args{copy_link};
    local $File::Copy::Recursive::RMTrgFil = $args{rm_file};
    local $File::Copy::Recursive::RMTrgDir = $args{rm_dir};
    local $File::Copy::Recursive::PFSCheck = $args{pfs_check};
    local $File::Copy::Recursive::CPRFComp = $args{cprf};

    require File::Copy::Recursive;

    if ( -d $from ) {
        if ( $args{glob} ) {
            return File::Copy::Recursive::rcopy_glob( qq[$from/$args{glob}], $to, $args{buf_size} // () );
        }
        else {
            return File::Copy::Recursive::dircopy( $from, $to, $args{buf_size} // () );
        }
    }
    elsif ( -f $from ) {
        return File::Copy::Recursive::fcopy( $from, $to, $args{buf_size} // () );
    }
    else {
        die qq[Source "$from" not exists];
    }

    return;
}

sub move ( $self, $from, $to, % ) {
    my %args = (
        dir_mode  => q[rwxr-xr-x],
        umask     => undef,
        buf_size  => undef,
        copy_link => 0,              # if 1 - symlinks will be copied as symlinks
        rm_file   => 1,              # remove target file before copying, 0 - off, 1 - die if can't remove, 2 - return if can't remove
        rm_dir    => 1,              # remove target dir before copying, 0 - off, 1 - die if can't remove, 2 - return if can't remove
        pfs_check => 1,
        cprf      => 1,              # only if $to is dir, if $to/ is exists put $from/ content into $to/ instead of replace $to/ with $from/
        @_[ 3 .. $#_ ],
    );

    my $umask_guard = defined $args{umask} ? $self->umask( $args{umask} ) : undef;

    local $File::Copy::Recursive::DirPerms = $self->calc_chmod( $args{dir_mode}, oct => 1 );
    local $File::Copy::Recursive::CopyLink = $args{copy_link};
    local $File::Copy::Recursive::RMTrgFil = $args{rm_file};
    local $File::Copy::Recursive::RMTrgDir = $args{rm_dir};
    local $File::Copy::Recursive::PFSCheck = $args{pfs_check};
    local $File::Copy::Recursive::CPRFComp = $args{cprf};

    require File::Copy::Recursive;

    if ( -d $from ) {
        if ( $args{glob} ) {
            return File::Copy::Recursive::rmove_glob( qq[$from/$args{glob}], $to, $args{buf_size} // () );
        }
        else {
            return File::Copy::Recursive::dirmove( $from, $to, $args{buf_size} // () );
        }
    }
    elsif ( -f $from ) {
        return File::Copy::Recursive::fmove( $from, $to, $args{buf_size} // () );
    }
    else {
        die qq[Source "$from" not exists];
    }

    return;
}

# FIND
sub find ( $self, $path, @ ) {
    my %args = (
        abs  => 0,    # return absolute path
        dir  => 1,    # return found dirs
        file => 1,    # return found files
        @_[ 2 .. $#_ - 1 ],
    );

    $path = P->path( $path, is_dir => 1 )->realpath or return;

    my $cb = $_[-1];

    my $chdir_guard;

    $chdir_guard = $self->chdir($path) if !$args{abs};

    my $read_dir;

    $read_dir = sub ($dirpath) {
        for my $file ( $self->read_dir($dirpath)->@* ) {
            $file = $dirpath . q[/] . Encode::decode( $Pcore::WIN_ENC, $file, Encode::FB_CROAK );

            if ( -d $file ) {
                $file = P->path( $file, is_dir => 1 );

                $cb->($file) if $args{dir};

                $read_dir->($file);
            }
            else {
                $file = P->path( $file, is_dir => 0 );

                $cb->($file) if $args{file};
            }
        }

        return;
    };

    $read_dir->( $args{abs} ? $path : q[./] );

    return;
}

# WHICH / WHERE
sub which ( $self, $filename ) {
    require File::Which;

    return File::Which::which($filename);
}

sub where ( $self, $filename ) {
    require File::Which;

    return File::Which::where($filename);
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitExcessComplexity                                                                          │
## │      │ 48                   │ * Subroutine "calc_umask" with high complexity score (25)                                                      │
## │      │ 122                  │ * Subroutine "calc_chmod" with high complexity score (25)                                                      │
## │      │ 248                  │ * Subroutine "read_lines" with high complexity score (27)                                                      │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::File

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
