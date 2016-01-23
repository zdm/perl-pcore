package Pcore::Core::Env::Resources;

use Pcore -class, -const;

has _lib         => ( is => 'ro',   isa => HashRef,  default => sub { {} }, init_arg => undef );
has _lib_order   => ( is => 'ro',   isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _storage     => ( is => 'lazy', isa => HashRef,  default => sub { {} }, clearer  => 1, init_arg => undef );
has _lib_storage => ( is => 'lazy', isa => HashRef,  default => sub { {} }, init_arg => undef );

const our $RESERVED_LIB_NAME => {
    pcore => 1,
    dist  => 1,
    temp  => 1,
};

# TODO
sub add_lib ( $self, $name, $path, $level ) {

    # die qq[resource lib "$name" already exists] if exists $self->_lib->{$name};

    # die qq[resource lib name "$name" is reserved] if exists $RESERVED_LIB_NAME->{$name};

    $self->_add_lib( $name, $path );

    return;
}

sub _add_lib ( $self, $name, $path ) {
    $self->_lib->{$name} = $path;

    unshift $self->_lib_order->@*, $name;

    $self->_clear_storage;

    return;
}

sub get_lib ( $self, $name ) {
    return $self->_lib->{$name};
}

sub get_storage ( $self, $name, $lib = undef ) {
    \my $libs = \$self->_lib;

    if ($lib) {
        die qq[resource lib is not exists "$lib"] if !exists $libs->{$lib};

        \my $lib_storage = \$self->_lib_storage;

        if ( !exists $lib_storage->{$lib}->{$name} ) {
            if ( -d $libs->{$lib} . $name ) {
                $lib_storage->{$lib}->{$name} = $libs->{$lib} . $name;
            }
            else {
                $lib_storage->{$lib}->{$name} = undef;
            }
        }

        return $lib_storage->{$lib}->{$name};
    }
    else {
        \my $storage = \$self->_storage;

        if ( !exists $storage->{$name} ) {
            my $index = {};

            for my $lib_name ( $self->_lib_order->@* ) {
                my $path = $libs->{$lib_name} . $name;

                if ( -d $path && !exists $index->{$path} ) {
                    $index->{$path} = 1;

                    push $storage->{$name}->@*, $path;
                }
            }

            $storage->{$name} = undef if !exists $storage->{$name};
        }

        return $storage->{$name};
    }
}

sub get ( $self, $path, @ ) {
    my %args = (
        storage => undef,
        lib     => undef,
        splice @_, 2,
    );

    die qq[resource lib is not exists "$args{lib}"] if $args{lib} && !exists $self->_lib->{ $args{lib} };

    # get storage name from path
    if ( !$args{storage} ) {
        if ( $path =~ m[\A/?([^/]+)/(.+)]sm ) {
            $args{storage} = $1;

            $path = P->path( q[/] . $2 );
        }
        else {
            die qq[invalid resource path "$path"];
        }
    }
    else {
        $path = P->path( q[/] . $path );
    }

    if ( $args{lib} ) {
        my $res = $self->_lib->{ $args{lib} } . $args{storage} . q[/] . $path;

        if ( -f $res ) {
            return $res;
        }
    }
    elsif ( my $storage = $self->get_storage( $args{storage} ) ) {
        for my $storage_root ( $storage->@* ) {
            my $res = $storage_root . $path;

            if ( -f $res ) {
                return $res;
            }
        }
    }

    return;
}

sub store ( $self, $file, $path, $lib, @ ) {
    my %args = (
        storage => undef,
        splice @_, 4,
    );

    die qq[resource lib is not exists "$lib"] if !exists $self->_lib->{$lib};

    # get storage name from path
    if ( !$args{storage} ) {
        if ( $path =~ m[\A/?([^/]+)/(.+)]sm ) {
            $args{storage} = $1;

            $path = P->path( q[/] . $2 );
        }
        else {
            die qq[invalid resource path "$path"];
        }
    }
    else {
        $path = P->path( q[/] . $path );
    }

    # clear storage cache if new storage was created
    if ( !-e $self->_lib->{$lib} . $args{storage} ) {
        delete $self->_storage->{ $args{storage} };

        delete $self->_lib_storage->{$lib}->{ $args{storage} };
    }

    # create path
    P->file->mkpath( $self->_lib->{$lib} . $args{storage} . $path->dirname ) if !-d $self->_lib->{$lib} . $args{storage} . $path->dirname;

    # create file
    if ( ref $file eq 'SCALAR' ) {
        P->file->write_bin( $self->_lib->{$lib} . $args{storage} . $path, $file );
    }
    else {
        P->file->copy( $file, $self->_lib->{$lib} . $args{storage} . $path );
    }

    return $self->_lib->{$lib} . $args{storage} . $path;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Env::Resources

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
