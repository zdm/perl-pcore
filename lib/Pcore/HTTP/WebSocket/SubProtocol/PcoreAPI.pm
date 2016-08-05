package Pcore::HTTP::WebSocket::SubProtocol::PcoreAPI;

use Pcore -role;

has websocket_subprotocol => ( is => 'ro', default => 'pcore-api', init_arg => undef );

with qw[Pcore::HTTP::WebSocket::SubProtocol];

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::WebSocket::SubProtocol::PcoreAPI

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
