package Pcore::App::API::Role;

use Pcore -role;

requires qw[_build_map];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has map => ( is => 'lazy', isa => HashRef, init_arg => undef );

around _build_map => sub ( $orig, $self ) {
    my $map = $self->$orig;

    # validate API class map

    # TODO check API description

    # TODO check, that methods are exists

    # TODO check api method description

    return $map;
};

sub api_call ( $self, @args ) {
    return $self->{api_session}->api_call(@args);
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Role

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
