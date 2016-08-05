package Pcore::HTTP::WebSocket::SubProtocol::Raw;

use Pcore -role;

has websocket_subprotocol => ( is => 'ro', default => undef, init_arg => undef );

with qw[Pcore::HTTP::WebSocket::SubProtocol];

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::WebSocket::SubProtocol::Raw

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
