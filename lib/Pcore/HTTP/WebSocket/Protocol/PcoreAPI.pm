package Pcore::HTTP::WebSocket::Protocol::PcoreAPI;

use Pcore -role;

has websocket_protocol => ( is => 'ro', default => 'pcore-api', init_arg => undef );

with qw[Pcore::HTTP::WebSocket::Protocol];

requires qw[websocket_on_binary];

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::WebSocket::Protocol::PcoreAPI

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
