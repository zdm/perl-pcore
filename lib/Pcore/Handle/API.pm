package Pcore::Handle::API;

use Pcore qw[-class];

with qw[Pcore::Core::H::Role::Wrapper];

has '+h_disconnect_on' => ( default => undef );

# remote API interface
has addr => ( is => 'ro', isa => Str, required => 1 );    # http://<host>

# H
sub h_connect {
    my $self = shift;

    my $h = P->class->load('Pcore::API::Backend::Remote')->new( { addr => $self->addr } );

    return $h;
}

sub h_disconnect {
    my $self = shift;

    $self->h->signout;

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
