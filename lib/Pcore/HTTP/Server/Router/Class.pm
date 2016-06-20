package Pcore::HTTP::Server::Router::Class;

use Pcore -class;

with qw[Pcore::HTTP::Server::Router];

sub run ( $self, $env ) {
    return [ 200, [ 'Content-Type' => 'text/html' ], [ 1, 2, 3 ] ];
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server::Router::Class

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
