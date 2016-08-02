package Pcore::App::API::Auth;

use Pcore -role;

requires qw[auth_password auth_token set_root_password upload_api_map];

has api => ( is => 'ro', isa => ConsumerOf ['Pcore::App::API'], required => 1 );

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
