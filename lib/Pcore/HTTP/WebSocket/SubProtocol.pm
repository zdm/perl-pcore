package Pcore::HTTP::WebSocket::SubProtocol;

use Pcore -const, -role;
use Pcore::HTTP::WebSocket::Util;

requires qw[websocket_subprotocol];

has h => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );
has max_frame_length => ( is => 'ro', isa => PositiveInt, default => 1024 * 1024 * 10 );

has status => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # remote close status

has _msg_op         => ( is => 'ro',   isa => Str,      init_arg => undef );
has _msg_buf        => ( is => 'ro',   isa => ArrayRef, init_arg => undef );
has _ping_callbacks => ( is => 'lazy', isa => ArrayRef, default  => sub { [] }, init_arg => undef );
has _close_sent => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

# http://www.iana.org/assignments/websocket/websocket.xml#extension-name
has ext_permessage_deflate => ( is => 'ro', isa => Bool, default => 0 );

const our $WS_VERSION => 13;
const our $WS_GUID    => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

# http://www.iana.org/assignments/websocket/websocket.xml#opcode
const our $WS_CONTINUATION => 0;
const our $WS_TEXT         => 1;
const our $WS_BINARY       => 2;
const our $WS_CLOSE        => 8;
const our $WS_PING         => 9;
const our $WS_PONG         => 10;

# http://www.iana.org/assignments/websocket/websocket.xml#close-code-number
const our $WS_CLOSE_REASON => {
    1000 => 'Normal Closure',
    1001 => 'Going Away',                   # удалённая сторона «исчезла». Например, процесс сервера убит или браузер перешёл на другую страницу
    1002 => 'Protocol error',
    1003 => 'Unsupported Data',
    1004 => 'Reserved',
    1005 => 'No Status Rcvd',
    1006 => 'Abnormal Closure',
    1007 => 'Invalid frame payload data',
    1008 => 'Policy Violation',
    1009 => 'Message Too Big',
    1010 => 'Mandatory Ext.',
    1011 => 'Internal Error',
    1012 => 'Service Restart',
    1013 => 'Try Again Later',
    1015 => 'TLS handshake',
};

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::WebSocket::SubProtocol

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
