package Pcore::API::Response;

use Pcore -class;

has status => ( is => 'ro', isa => PositiveInt, required => 1 );
has reason => ( is => 'lazy', isa => Str );

with qw[Pcore::HTTP::Status];

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Response

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
