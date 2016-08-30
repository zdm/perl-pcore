package Pcore::App::API::Auth::Backend::Local;

use Pcore -role;

with qw[Pcore::App::API::Auth::Backend];

has dbh => ( is => 'ro', isa => ConsumerOf ['Pcore::DBH'], required => 1 );

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Backend::Local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
