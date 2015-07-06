package Pcore::Core::H::Role::Wrapper;

use Pcore qw[-role -autoload];

with qw[Pcore::Core::H::Role];

requires qw[h_connect];

has h => ( is => 'lazy', builder => 'h_connect', predicate => 'h_is_connected', clearer => 1, init_arg => undef );

around h_disconnect => sub {
    my $orig = shift;
    my $self = shift;

    if ( $self->h_is_connected ) {
        $self->$orig if defined $self->{h};

        $self->clear_h;
    }

    return;
};

sub autoload {
    my $self   = shift;
    my $method = shift;

    return sub {
        my $self = shift;

        return $self->h->$method(@_);
    }, not_create_method => 0;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::H::Role::Wrapper

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
