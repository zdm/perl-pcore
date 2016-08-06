package Pcore::HTTP::WebSocket::Protocol::PcoreRPC;

use Pcore -role;

has websocket_protocol => ( is => 'ro', default => 'pcore-rpc', init_arg => undef );

with qw[Pcore::HTTP::WebSocket::Protocol];

requires qw[websocket_on_text websocket_on_binary];

# text - json
# binary - cbor

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::WebSocket::Protocol::PcoreRPC

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
