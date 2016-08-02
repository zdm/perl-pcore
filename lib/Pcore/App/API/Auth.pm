package Pcore::API::Server::Auth;

use Pcore -role;

requires qw[auth_password auth_token set_root_password upload_api_map];

has api => ( is => 'ro', isa => ConsumerOf ['Pcore::API::Server'], required => 1 );

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Server::Auth

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
