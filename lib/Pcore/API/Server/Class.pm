package Pcore::API::Server::Class;

use Pcore -role;

requires qw[_build_map];

has map => ( is => 'lazy', isa => HashRef, init_arg => undef );

around _build_map => sub ( $orig, $self ) {
    my $map = $self->$orig;

    # validate API class map

    # TODO check, that methods are exists

    return $map;
};

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Server::Class

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
