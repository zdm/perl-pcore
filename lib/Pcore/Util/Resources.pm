package Pcore::Util::Resources;

use Pcore;

no Pcore;

sub dist_dir {
    state $dir = do {
        my $_dir;

        if ($Pcore::IS_PAR) {    # PAR
            $_dir = _init_resources_root( $ENV{PAR_TEMP} . '/inc/resources/' );
        }
        elsif ( $DIST->{ROOT} ) {    # dist
            $_dir = _init_resources_root( $DIST->{ROOT} . 'resources/' );
        }

        $_dir;
    };

    return $dir;
}

sub pcore_dir {
    state $dir = do {
        my $_dir;

        if ( $P->{ROOT} ) {    # Pcore is dist
            if ( $ENV{PCORE_RESOURCES} && -d $ENV{PCORE_RESOURCES} ) {
                $_dir = _init_resources_root( $ENV{PCORE_RESOURCES} );    # take dir from ENV
            }
            elsif ( -d $P->{ROOT} . 'resources/' ) {
                $_dir = _init_resources_root( $P->{ROOT} . 'resources/' );    # take from dist rources dir
            }
        }
        else {                                                                # Pcore is located in CPAN or PAR
            if ( $ENV{PCORE_RESOURCES} && -d $ENV{PCORE_RESOURCES} ) {
                $_dir = _init_resources_root( $ENV{PCORE_RESOURCES} );        # take dir from ENV
            }
        }

        $_dir;
    };

    return $dir;
}

sub mounted_dir {
    state $dir = do {
        my $_dir;

        if ( $ENV{PCORE_MOUNTED_RESOURCES} && -d $ENV{PCORE_MOUNTED_RESOURCES} ) {
            $_dir = _init_resources_root( $ENV{PCORE_MOUNTED_RESOURCES} );
        }

        $_dir;
    };

    return $dir;
}

sub _init_resources_root ($root) {
    P->file->mkpath($root) if !-d $root;

    $root = P->path( $root, is_dir => 1 )->realpath->to_string;

    P->file->mkdir( $root . '/local/' ) if !-d $root . '/local/';

    P->file->mkdir( $root . '/share/' ) if !-d $root . '/share/';

    return $root;
}

sub get_root ($self) {
    state $root = do {
        my $_root = [];

        my $index;

        if ( mounted_dir() ) {
            $index->{ mounted_dir() } = 1;

            push $_root->@*, mounted_dir();
        }

        if ( dist_dir() ) {
            $index->{ dist_dir() } = 1;

            push $_root->@*, dist_dir();
        }

        if ( pcore_dir() ) {
            $index->{ pcore_dir() } = 1;

            push $_root->@*, pcore_dir();
        }

        $_root;
    };

    return $root;
}

sub get_local ( $self, $path ) {
    for my $root ( $self->get_root->@* ) {
        if ( my $found_path = $self->_find_resource( $root, 'local', $path ) ) {
            return $found_path;
        }
    }

    return;
}

sub get_share ( $self, $path ) {
    for my $root ( $self->_get_root->@* ) {
        if ( my $found_path = $self->_find_resource( $root, 'share', $path ) ) {
            return $found_path;
        }
    }

    return;
}

sub _find_resource ( $self, $root, $location, $path ) {
    state $location_cache = {};

    # cache location
    $location_cache->{$root}->{$location} = $root . $location . q[/] if !exists $location_cache->{$root}->{$location};

    # get location from cache
    $root = $location_cache->{$root}->{$location};

    if ( -f $root . $path ) {
        my $realpath = P->path( $root . $path )->realpath->to_string;

        return $realpath if index( $realpath, $root, 0 ) == 0;
    }

    return;
}

sub copy_local ( $self, $from, $to ) {
    for my $root ( reverse $self->get_root->@* ) {
        P->file->copy( qq[$root/local/$from], qq[$to/local/$from] ) if -e qq[$root/local/$from];
    }

    return;
}

sub copy_share ( $self, $from, $to ) {
    for my $root ( reverse $self->get_root->@* ) {
        P->file->copy( qq[$root/share/$from], qq[$to/share/$from] ) if -e qq[$root/share/$from];
    }

    return;
}

sub store_local ( $self, $path, $file ) {
    return $self->_store_resource( 'local', $path, $file );
}

sub store_share ( $self, $path, $file ) {
    return $self->_store_resource( 'share', $path, $file );
}

sub _store_resource ( $self, $location, $path, $file ) {
    if ( dist_dir() ) {
        my $store_path = P->path( dist_dir() . $location . q[/] . $path );

        P->file->mkpath( $store_path->dirname ) if $store_path->dirname && !-d $store_path->dirname;

        if ( ref $file eq 'SCALAR' ) {
            P->file->write_bin( $store_path, $file );
        }
        else {
            P->file->copy( $file, $store_path );
        }

        return $store_path;
    }
    else {
        die q[Resource storage is not present];
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 67, 69, 133          │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Resources

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
