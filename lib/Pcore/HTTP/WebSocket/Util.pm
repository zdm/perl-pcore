package Pcore::HTTP::WebSocket::Util;

use Pcore -const, -export => { CONST => [qw[$WEBSOCKET_VERSION $WEBSOCKET_OP_CONTINUATION $WEBSOCKET_OP_TEXT $WEBSOCKET_OP_BINARY $WEBSOCKET_OP_CLOSE $WEBSOCKET_OP_PING $WEBSOCKET_OP_PONG]] };
use Pcore::Util::Data qw[to_b64 to_xor];
use Digest::SHA1 qw[];
use Compress::Raw::Zlib;

const our $WEBSOCKET_VERSION => 13;
const our $WEBSOCKET_GUID    => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

# http://www.iana.org/assignments/websocket/websocket.xml#opcode
const our $WEBSOCKET_OP_CONTINUATION => 0;
const our $WEBSOCKET_OP_TEXT         => 1;
const our $WEBSOCKET_OP_BINARY       => 2;
const our $WEBSOCKET_OP_CLOSE        => 8;
const our $WEBSOCKET_OP_PING         => 9;
const our $WEBSOCKET_OP_PONG         => 10;

# http://www.iana.org/assignments/websocket/websocket.xml#close-code-number
const our $WEBSOCKET_CLOSE_REASON => {
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

sub get_challenge ( $key ) {
    return to_b64( Digest::SHA1::sha1( ( $key || q[] ) . $WEBSOCKET_GUID ), q[] );
}

sub parse_frame_header ( $buf_ref ) {
    return if length $buf_ref->$* < 2;

    my ( $first, $second ) = unpack 'C*', substr( $buf_ref->$*, 0, 2 );

    my $masked = $second & 0b10000000;

    my $header;

    ( my $hlen, $header->{len} ) = ( 2, $second & 0b01111111 );

    # small payload
    if ( $header->{len} < 126 ) {
        $hlen += 4 if $masked;

        return if length $buf_ref->$* < $hlen;

        # cut header
        my $full_header = substr $buf_ref->$*, 0, $hlen, q[];

        $header->{mask} = substr $full_header, 2, 4, q[] if $masked;
    }

    # extended payload (16-bit)
    elsif ( $header->{len} == 126 ) {
        $hlen = $masked ? 8 : 4;

        return if length $buf_ref->$* < $hlen;

        # cut header
        my $full_header = substr $buf_ref->$*, 0, $hlen, q[];

        $header->{mask} = substr $full_header, 4, 4, q[] if $masked;

        $header->{len} = unpack 'n', substr $full_header, 2, 2, q[];
    }

    # extended payload (64-bit with 32-bit fallback)
    elsif ( $header->{len} == 127 ) {
        $hlen = $masked ? 10 : 14;

        return if length $buf_ref->$* < $hlen;

        # cut header
        my $full_header = substr $buf_ref->$*, 0, 10, q[];

        $header->{mask} = substr $full_header, 10, 4, q[] if $masked;

        $header->{len} = unpack 'Q>', substr $full_header, 2, 8, q[];
    }

    # FIN
    $header->{fin} = ( $first & 0b10000000 ) == 0b10000000 ? 1 : 0;

    # RSV1-3
    $header->{rsv1} = ( $first & 0b01000000 ) == 0b01000000 ? 1 : 0;
    $header->{rsv2} = ( $first & 0b00100000 ) == 0b00100000 ? 1 : 0;
    $header->{rsv3} = ( $first & 0b00010000 ) == 0b00010000 ? 1 : 0;

    # opcode
    $header->{op} = $first & 0b00001111;

    return $header;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 45, 47               | NamingConventions::ProhibitAmbiguousNames - Ambiguously named variable "second"                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 45                   | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::WebSocket::Util

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
