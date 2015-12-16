package Pcore::Handle::Object;

use Pcore -class;

with qw[Pcore::Core::H::Role::Wrapper];

has h_class => ( is => 'ro', isa => Str | Object, required => 1 );
has h_class_constructor => ( is => 'lazy', isa => HashRef, default => sub { {} } );
has h_disconnect_method => ( is => 'ro', isa => Str, predicate => 1 );

# H
sub h_connect {
    my $self = shift;

    return P->scalar->blessed( $self->h_class ) ? $self->h_class : P->class->load( $self->h_class )->new( $self->h_class_constructor );
}

sub h_disconnect {
    my $self = shift;

    if ( $self->has_h_disconnect_method ) {
        my $method = $self->h_disconnect_method;
        $self->h->$method;
    }

    return;
}

around clear_h => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig unless $self->has_h_disconnect_method;

    return;
};

1;
__END__
=pod

=encoding utf8

=cut
