package Pcore::HTTP::Server::Controller;

use Pcore -role;

has env => ( is => 'ro', isa => HashRef, required => 1 );
has router => ( is => 'ro', isa => ConsumerOf ['Pcore::HTTP::Server::Router'], required => 1 );
has path      => ( is => 'ro', isa => Str, required => 1 );
has path_tail => ( is => 'ro', isa => Str, required => 1 );

requires qw[run];

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server::Controller

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
