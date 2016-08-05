package Pcore::App::Controller::WebSocket;

use Pcore -role;

with qw[Pcore::App::Controller Pcore::HTTP::WebSocket::Server Pcore::HTTP::WebSocket::Protocol::Raw];

requires qw[run];

sub websocket_can_accept ( $self ) {
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
