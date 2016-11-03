package Pcore::App::API::Auth::Cache;

use Pcore -class;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has private_token => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has auth          => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Cache

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
