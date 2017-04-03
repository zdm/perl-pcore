package Pcore::RPC::Connection;

use Pcore -class;
use Pcore::Util::Data qw[to_cbor from_json from_cbor];

with qw[Pcore::App::Controller::WebSocket];

has '+websocket_subprotocol'        => ( default => 'pcore-rpc' );
has '+websocket_max_message_size'   => ( default => 0 );
has '+websocket_permessage_deflate' => ( default => 0 );
has '+websocket_autopong'           => ( default => 3 );

has ws => ( is => 'ro', init_arg => undef );

sub run ( $self, $req ) {
    $req->return_xxx(400);

    return;
}

sub rpc_call ( $self, $method, $args, $cb = undef ) {
    my $payload = [ $method, $args ];

    $self->{ws}->send_binary( to_cbor($payload)->$* );

    return;
}

sub websocket_on_connect ( $self, $ws ) {
    say 'CONNECTED';

    $self->{ws} = $ws;

    return;
}

sub websocket_on_text ( $self, $payload_ref ) {
    return;
}

sub websocket_on_binary ( $self, $payload_ref ) {
    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::RPC::Connection

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
