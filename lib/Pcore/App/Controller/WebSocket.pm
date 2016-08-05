package Pcore::App::Controller::WebSocket;

use Pcore -role;

# NOTE WebSocket::Server role must be before WebSocket::Protocol
with qw[Pcore::App::Controller Pcore::HTTP::WebSocket::Server Pcore::HTTP::WebSocket::Protocol::Raw];

# NOTE perform additional checks, return true or headers array on success, or false, if connection is not possible
sub websocket_on_accept ( $self ) {
    return 1;
}

sub websocket_on_text ( $self, $data_ref ) {
    say dump $data_ref;

    return;
}

sub websocket_on_binary ( $self, $data_ref ) {
    say dump $data_ref;

    return;
}

sub websocket_on_close ( $self, $status ) {
    say 'WEBSOCKET CLOSED: ' . $status;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::Controller::WebSocket

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
