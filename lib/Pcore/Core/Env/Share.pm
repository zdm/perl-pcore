package Pcore::Core::Env::Share;

use Pcore -class, -const;
use Pcore::Util::Scalar qw[is_plain_scalarref is_plain_arrayref is_plain_hashref];

has _temp        => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::File::TempDir'], init_arg => undef );
has _lib         => ( is => 'ro',   isa => HashRef,                                   init_arg => undef );    # name => [$level, $path]
has _storage     => ( is => 'ro',   isa => HashRef,                                   init_arg => undef );    # storage cache, name => [$path, ...]
has _lib_storage => ( is => 'ro',   isa => HashRef,                                   init_arg => undef );    # lib storage cache, {lib}->{storage} = $path

const our $RESERVED_LIB_NAME => {
    dist => 1,                                                                                                # alias for main dist
    temp => 1,                                                                                                # temporary resources lib
};

sub _build__temp ($self) {
    return P->file->tempdir;
}

sub add_lib ( $self, $name, $path, $level ) {
    die qq[resource lib name "$name" is reserved] if exists $RESERVED_LIB_NAME->{$name};

    die qq[resource lib "$name" already exists] if exists $self->{_lib}->{$name};

    # register lib
    $self->{_lib}->{$name} = [ $level, $path ];

    # clear cache
    delete $self->{_storage};

    return;
}

# return lib path by name
sub get_lib ( $self, $name ) {
    if ( $ENV->is_par ) {

        # under the PAR all resources libs are merged under the "dist" alias
        return $self->{_lib}->{dist}->[1];
    }
    elsif ( $name eq 'temp' ) {
        return $self->_temp->path;
    }
    else {
        if ( $name eq 'dist' ) {
            if ( $ENV->{main_dist} ) {
                $name = $ENV->{main_dist}->name;
            }
            else {
                return;
            }
        }

        return exists $self->{_lib}->{$name} ? $self->{_lib}->{$name}->[1] : ();
    }
}

# return undef if storage is not exists
# return $storage_path if lib is specified
# return ArrayRef[$storage_path] if lib is not specified
sub get_storage1 ( $self, @ ) {
    my ( $lib, $path );

    if ( @_ == 2 ) {
        $path = $_[1];
    }
    elsif ( @_ == 3 ) {
        $lib = $_[1];

        $path = $_[2];
    }

    if ($lib) {
        my $lib1 = $self->{_lib}->{$lib};

        die qq[share lib "$lib" is not exists] if !$lib1;

        return -d $lib1->[1] . $path ? $lib1->[1] . $path : ();
    }
    else {
        my @res;

        for my $lib ( values $self->{_lib}->%* ) {
            push @res, $lib->[1] . $path if -d $lib->[1] . $path;
        }

        return \@res;
    }
}

sub get ( $self, @ ) {
    my ( $lib, $root, $path );

    if ( @_ == 2 ) {
        $path = $_[1];
    }
    elsif ( @_ == 3 ) {
        ( $root, $path ) = ( $_[1], $_[2] );
    }
    elsif ( @_ == 4 ) {
        ( $lib, $root, $path ) = ( $_[1], $_[2], $_[3] );
    }

    for my $lib1 ( $lib ? $self->{_lib}->{$lib} // () : values $self->{_lib}->%* ) {
        my $root_path = $lib1->[1];

        $root_path .= $root if $root;

        my $real_path = Cwd::realpath("$root_path/$path");

        if ( -f $real_path ) {

            # convert slashes
            $path =~ s[\\][/]smg;

            if ( substr( $real_path, 0, length $root_path ) eq $root_path ) {
                return $real_path;
            }
        }
    }

    return;
}

sub store ( $self, $lib, $path, $file ) {
    my $lib1 = $self->{_lib}->{$lib};

    die qq[share lib "$lib" is not exists] if !$lib1;

    $path = P->path( $lib1->[1] . $path );

    # create path
    P->file->mkpath( $path->dirname ) if !-d $path->dirname;

    # create file
    if ( is_plain_scalarref $file ) {
        P->file->write_bin( $path, $file );
    }
    elsif ( is_plain_arrayref $file || is_plain_hashref $file ) {
        P->cfg->store( $path, $file, readable => 1 );
    }
    else {
        P->file->copy( $file, $path );
    }

    return $path;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Env::Share

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
