package Pcore::PSGI::Middleware;

use Pcore qw[-class];

extends qw[Plack::Middleware];

has app => ( is => 'ro', isa => CodeRef, required => 1 );

1;
__END__
=pod

=encoding utf8

=cut
