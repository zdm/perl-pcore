package Pcore::HTTP::WebSocket::Protocol::PcoreRPC;

use Pcore -role;
use Pcore::Util::Data qw[from_json from_cbor];

has websocket_protocol => ( is => 'ro', default => 'pcore-rpc', init_arg => undef );

with qw[Pcore::HTTP::WebSocket::Protocol];

sub rpc_call ( $self, $method, $data, $cb = undef ) {
    $self->websocket_send_binary( P->data->to_cbor( [ $method, $data ] )->$* );

    return;
}

# message protocol:
# [$method_name, $callback_id, \@args]
sub _on_message ( $self, $data ) {
    say dump $data;

    return;
}

sub websocket_on_text ( $self, $payload_ref ) {
    $self->_on_message( from_json $payload_ref);

    return;
}

sub websocket_on_binary ( $self, $payload_ref ) {
    $self->_on_message( from_cbor $payload_ref);

    return;
}

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
