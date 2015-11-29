package Pcore::Core::Proc::Res;

use Pcore qw[-class];

has lib          => ( is => 'ro',   isa => HashRef,  default => sub { {} }, init_arg => undef );
has lib_order    => ( is => 'ro',   isa => ArrayRef, default => sub { [] }, init_arg => undef );
has storage_root => ( is => 'lazy', isa => HashRef,  default => sub { {} }, clearer  => 1, init_arg => undef );

no Pcore;

sub add_lib ( $self, $name, $path ) {
    die qq[resource lib "$name" already exists] if exists $self->lib->{$name};

    $self->lib->{$name} = $path;

    unshift $self->lib_order->@*, $name;

    $self->clear_storage_root;

    return;
}

sub get_storage_root ( $self, $name ) {
    \my $storage_root = \$self->storage_root;

    if ( !exists $storage_root->{$name} ) {
        for my $lib_name ( $self->lib_order->@* ) {
            push $storage_root->{$name}->@*, $self->lib->{$lib_name} . $name . q[/] if -d $self->lib->{$lib_name} . $name . q[/];
        }

        $storage_root->{$name} = undef if !exists $storage_root->{$name};
    }

    return $storage_root->{$name};
}

sub get ( $self, $path, @ ) {
    my %args = (
        storage => undef,
        lib     => undef,
        @_[ 2 .. $#_ ],
    );

    if ( !$args{storage} ) {
        if ( $path =~ m[(.+)?/]sm ) {
            $args{storage} = $1;
        }
        else {
            die qq[invalid resource path "$path"];
        }
    }

    if ( $args{lib} ) {
        die qq[resource lib is not exists "$args{lib}"] if !exists $self->lib->{ $args{lib} };

        my $res = $self->lib->{ $args{lib} } . $args{storage} . q[/] . $path;

        if ( -f $res ) {
            return $res;
        }
        else {
            return;
        }
    }
    elsif ( my $storage_root = $self->get_storage_root( $args{storage} ) ) {
        for my $root ( $storage_root->@* ) {
            my $res = $root . $path;

            return $res if -f $res;
        }
    }

    return;
}

sub store ( $self, @ ) {
    my %args = (
        lib     => undef,
        storage => undef,
        @_[ 2 .. $#_ ],
    );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Proc::Res

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
