package Pcore::JS::ExtJS::Request;

use Pcore -class;
use Pcore::JS::ExtJS::Class::Descriptor;

has app_ns     => ( is => 'ro', isa => Str, required => 1 );
has class_ns   => ( is => 'ro', isa => Str, required => 1 );
has class_name => ( is => 'ro', isa => Str, required => 1 );

has requires => ( is => 'lazy', isa => ArrayRef, default => sub { [] }, predicate => 1, init_arg => undef );

has _descriptors_cache => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

no Pcore;

sub class {
    my $self = shift;
    my $desc = shift;
    my %args = (
        require => 0,
        @_,
    );

    $desc =~ s[/][.]smg if $desc;

    my $descriptor = $self->get_descriptor( $desc || $self->class_name );

    $self->add_requires( [$descriptor] ) if $desc && $args{require};

    return $descriptor->class;
}

sub type {
    my $self = shift;
    my $desc = shift;

    $desc =~ s[/][.]smg if $desc;

    my $descriptor = $self->get_descriptor( $desc || $self->class_name );

    $self->add_requires( [$descriptor] ) if $desc;

    return $descriptor->type;
}

sub add_requires {
    my $self     = shift;
    my $requires = shift;

    push $self->requires, $requires->@*;

    return;
}

sub get_descriptor {
    my $self = shift;
    my $desc = shift;

    if ( !$self->_descriptors_cache->{$desc} ) {
        $self->_descriptors_cache->{$desc} = Pcore::JS::ExtJS::Class::Descriptor->new(
            {   descriptor => $desc,
                app_ns     => $self->app_ns,
                class_ns   => $self->class_ns,
                class_name => $self->class_name,
            }
        );
    }

    return $self->_descriptors_cache->{$desc};
}

1;
__END__
=pod

=encoding utf8

=cut
