package Pcore::App::Controller::WebSocket;

use Pcore -role;
use Pcore::Util::Scalar qw[refaddr];

has ws_protocol => ( is => 'ro', isa => Maybe [Str], builder => '_build_ws_protocol' );
has ws_max_message_size => ( is => 'ro', isa => PositiveOrZeroInt, builder => '_build_ws_max_message_size' );    # 0 - do not check
has ws_permessage_deflate => ( is => 'ro', isa => Bool, builder => '_build_ws_permessage_deflate' );

# send pong automatically on handle timeout
# this parameter should be less, than nginx "proxy_read_timeout" in nginx
has ws_autopong => ( is => 'ro', isa => PositiveOrZeroInt, builder => '_build_ws_autopong' );    # 0 - do not pong on timeout

with qw[Pcore::App::Controller Pcore::HTTP::WebSocket::Server];

has _websocket_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

sub _build_ws_protocol ($self) {
    return;
}

sub _build_ws_max_message_size ($self) {
    return 1024 * 1024 * 10;
}

sub _build_ws_permessage_deflate ($self) {
    return 0;
}

sub _build_ws_autopong ($self) {
    return 50;
}

around ws_disconnect => sub ( $orig, $self, $ws, $status, $reason = undef ) {

    # remove websocket connection from cache
    delete $self->{_websocket_cache}->{ refaddr $ws};

    $ws->disconnect( $status, $reason );

    return $self->$orig( $ws, $status, $ws->{reason} );
};

around ws_on_disconnect => sub ( $orig, $self, $ws, $status, $reason ) {

    # remove websocket connection from cache
    delete $self->{_websocket_cache}->{ refaddr $ws};

    return $self->$orig( $ws, $status, $reason );
};

# called, before websocket connection accept
# should return $accept, \@headers = undef
# needed connection variables can  de stored in the $ws object attributes for further usage
sub ws_on_accept ( $self, $ws, $req, $accept, $decline ) {
    $accept->();

    return;
}

# called, when websocket connection is accepted and ready for use
sub ws_on_connect ( $self, $ws ) {
    return;
}

sub ws_on_text ( $self, $ws, $data_ref ) {
    return;
}

sub ws_on_binary ( $self, $ws, $data_ref ) {
    return;
}

sub ws_on_pong ( $self, $ws, $data_ref = undef ) {
    return;
}

# should be called, when local peer decided to close connection
sub ws_disconnect ( $self, $ws, $status, $reason = undef ) {
    return;
}

# called, when remote peer close connection or on protocol errors
sub ws_on_disconnect ( $self, $ws, $status, $reason ) {
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
