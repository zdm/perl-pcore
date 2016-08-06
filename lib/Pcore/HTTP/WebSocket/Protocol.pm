package Pcore::HTTP::WebSocket::Protocol;

use Pcore -const, -role;
use Pcore::Util::Text qw[decode_utf8 encode_utf8];
use Pcore::Util::Data qw[to_b64 to_xor];
use Compress::Raw::Zlib;
use Digest::SHA1 qw[];

# https://tools.ietf.org/html/rfc6455

requires qw[websocket_protocol websocket_on_text websocket_on_binary websocket_on_close];

has websocket_max_message_size => ( is => 'ro', isa => PositiveOrZeroInt, default => 1024 * 1024 * 10 );    # 0 - do not check

# http://www.iana.org/assignments/websocket/websocket.xml#extension-name
# https://tools.ietf.org/html/rfc7692#page-10
has websocket_permessage_deflate => ( is => 'ro', isa => Bool, default => 0 );

has _websocket_msg => ( is => 'ro', isa => ArrayRef, init_arg => undef );    # fragmentated message data, [$payload, $op, $rsv1]
has _websocket_deflate => ( is => 'ro', init_arg => undef );
has _websocket_inflate => ( is => 'ro', init_arg => undef );

has _websocket_h => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'], init_arg => undef );
has websocket_status => ( is => 'ro', isa => Bool, init_arg => undef );      # close status, undef - opened
has websocket_reason => ( is => 'ro', isa => Str,  init_arg => undef );      # close reason, undef - opened

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

sub websocket_send_text ( $self, $payload ) {
    $self->{_websocket_h}->push_write( $self->_websocket_build_frame( 1, $self->{websocket_permessage_deflate}, 0, 0, $WEBSOCKET_OP_TEXT, 0, \encode_utf8 $payload) );

    return;
}

sub websocket_send_binary ( $self, $payload ) {
    $self->{_websocket_h}->push_write( $self->_websocket_build_frame( 1, $self->{websocket_permessage_deflate}, 0, 0, $WEBSOCKET_OP_BINARY, 0, \$payload ) );

    return;
}

sub websocket_ping ($self) {
    my $payload = time;

    $self->{_websocket_h}->push_write( $self->_websocket_build_frame( 1, 0, 0, 0, $WEBSOCKET_OP_PING, 0, \$payload ) );

    return;
}

sub websocket_close ( $self, $status, $reason = undef ) {

    # connection already closed
    return if defined $self->{websocket_status};

    # mark connection as closed
    $self->{websocket_status} = $status;

    $self->{websocket_reason} = $reason //= $WEBSOCKET_CLOSE_REASON->{$status} // 'Unknown reason';

    # cleanup fragmentated message data
    undef $self->{_websocket_msg};

    # send close message
    $self->{_websocket_h}->push_write( $self->_websocket_build_frame( 1, 0, 0, 0, $WEBSOCKET_OP_CLOSE, 0, \( pack( 'n', $status ) . encode_utf8 $reason ) ) );

    # destroy handle
    $self->{_websocket_h}->destroy;

    return;
}

# this callback can be redefined in subclasses
sub websocket_on_pong ( $self, $payload_ref ) {
    return;
}

# UTILS
sub websocket_challenge ( $self, $key ) {
    return to_b64( Digest::SHA1::sha1( ( $key || q[] ) . $WEBSOCKET_GUID ), q[] );
}

sub websocket_listen ($self) {

    # cleanup fragmentated message data
    undef $self->{_websocket_msg};

    $self->{_websocket_h}->on_error(
        sub ( $h, @ ) {
            $self->_websocket_on_close(1001) if !defined $self->{websocket_status};    # 1001 - Going Away

            return;
        }
    );

    $self->{_websocket_h}->on_read(
        sub ($h) {
            if ( my $header = $self->_websocket_parse_frame_header( \$h->{rbuf} ) ) {

                # check protocol errors
                if ( $header->{fin} ) {

                    # this is the last frame of the fragmentated message
                    if ( $header->{op} == $WEBSOCKET_OP_CONTINUATION ) {

                        # message was not started, return 1002 - protocol error
                        return $self->_websocket_on_close(1002) if !$self->{_websocket_msg};

                        # restore message "op", "rsv1"
                        ( $header->{op}, $header->{rsv1} ) = ( $self->{_websocket_msg}->[1], $self->{_websocket_msg}->[2] );
                    }

                    # this is the single-frame message
                    else {

                        # set "rsv1" flag
                        $header->{rsv1} = $self->{websocket_permessage_deflate} && $header->{rsv1} ? 1 : 0;
                    }
                }
                else {

                    # this is the next frame of the fragmentated message
                    if ( $header->{op} == $WEBSOCKET_OP_CONTINUATION ) {

                        # message was not started, return 1002 - protocol error
                        return $self->_websocket_on_close(1002) if !$self->{_websocket_msg};

                        # restore "rsv1" flag
                        $header->{rsv1} = $self->{_websocket_msg}->[2];
                    }

                    # this is the first frame of the fragmentated message
                    else {

                        # store message "op"
                        $self->{_websocket_msg}->[1] = $header->{op};

                        # set and store "rsv1" flag
                        $self->{_websocket_msg}->[2] = $header->{rsv1} = $self->{websocket_permessage_deflate} && $header->{rsv1} ? 1 : 0;
                    }
                }

                # empty frame
                if ( !$header->{len} ) {
                    $self->_on_frame( $header, undef );
                }
                else {

                    # check max. message size, return 1009 - message too big
                    if ( $self->{websocket_max_message_size} ) {
                        if ( $self->{_websocket_msg} && $self->{_websocket_msg}->[0] ) {
                            return $self->_websocket_on_close(1009) if $header->{len} + length $self->{_websocket_msg}->[0] > $self->{websocket_max_message_size};
                        }
                        else {
                            return $self->_websocket_on_close(1009) if $header->{len} > $self->{websocket_max_message_size};
                        }
                    }

                    if ( length $h->{rbuf} >= $header->{len} ) {
                        $self->_websocket_on_frame( $header, \substr $h->{rbuf}, 0, $header->{len}, q[] );
                    }
                    else {
                        $h->unshift_read(
                            chunk => $header->{len},
                            sub ( $h, $payload ) {
                                $self->_websocket_on_frame( $header, \$payload );

                                return;
                            }
                        );
                    }
                }
            }

            return;
        }
    );

    return;
}

sub _websocket_on_frame ( $self, $header, $payload_ref ) {

    if ($payload_ref) {

        # unmask
        $payload_ref = \to_xor( $payload_ref->$*, $header->{mask} ) if $header->{mask};

        # decompress
        if ( $header->{rsv1} ) {
            my $inflate = $self->{_websocket_inflate} ||= Compress::Raw::Zlib::Inflate->new(
                -WindowBits => -15,
                ( $self->{websocket_max_message_size} ? ( -Bufsize => $self->{websocket_max_message_size} ) : () ),
                -AppendOutput => 0,
                -ConsumeInput => 1,
                -LimitOutput  => 1,
            );

            $payload_ref->$* .= "\x00\x00\xff\xff";

            $inflate->inflate( $payload_ref, my $out );

            return $self->_websocket_on_close(1009) if length $payload_ref->$*;

            $payload_ref = \$out;
        }
    }

    # this is message fragment frame
    if ( !$header->{fin} ) {

        # add frame to the message buffer
        $self->{_websocket_msg}->[0] .= $payload_ref->$* if $payload_ref;
    }

    # message completed, dispatch message
    else {
        if ( $self->{_websocket_msg} ) {
            $payload_ref = \( $self->{_websocket_msg}->[0] . $payload_ref->$* ) if $payload_ref && defined $self->{_websocket_msg}->[0];

            # cleanup fragmentated message data
            undef $self->{_websocket_msg};
        }

        # dispatch message
        if ( $header->{op} == $WEBSOCKET_OP_TEXT ) {
            if ($payload_ref) {
                decode_utf8 $payload_ref->$*;

                $self->websocket_on_text($payload_ref);
            }
        }
        elsif ( $header->{op} == $WEBSOCKET_OP_BINARY ) {
            $self->websocket_on_binary($payload_ref) if $payload_ref;
        }
        elsif ( $header->{op} == $WEBSOCKET_OP_CLOSE ) {
            my ( $status, $reason );

            if ( $payload_ref && length $payload_ref->$* >= 2 ) {
                $status = unpack 'n', substr $payload_ref->$*, 0, 2, q[];

                $reason = decode_utf8 $payload_ref->$* if length $payload_ref->$*;
            }
            else {
                $status = 1006;    # 1006 - Abnormal Closure - if close status was not specified
            }

            $self->_websocket_on_close( $status, $reason );
        }
        elsif ( $header->{op} == $WEBSOCKET_OP_PING ) {

            # send pong
            $self->{_websocket_h}->push_write( $self->_websocket_build_frame( 1, 0, 0, 0, $WEBSOCKET_OP_PONG, 0, $payload_ref ) );
        }
        elsif ( $header->{op} == $WEBSOCKET_OP_PONG ) {
            $self->websocket_on_pong($payload_ref);
        }
    }

    return;
}

# called automatically, when remote peer close connection
sub _websocket_on_close ( $self, $status, $reason = undef ) {

    # connection already closed
    return if defined $self->{websocket_status};

    $reason //= $WEBSOCKET_CLOSE_REASON->{$status} // 'Unknown reason';

    # close connection
    $self->websocket_close( $status, $reason );

    # call the websocket_on_close method
    $self->websocket_on_close( $status, $reason );

    return;
}

sub _websocket_build_frame ( $self, $fin, $rsv1, $rsv2, $rsv3, $op, $masked, $payload_ref ) {

    # deflate
    if ($rsv1) {
        my $deflate = $self->{_websocket_deflate} ||= Compress::Raw::Zlib::Deflate->new(
            -Level        => Z_DEFAULT_COMPRESSION,
            -WindowBits   => -15,
            -MemLevel     => 8,
            -AppendOutput => 0,
        );

        $deflate->deflate( $payload_ref, my $out ) == Z_OK or die q[Deflate error];

        $deflate->flush( $out, Z_SYNC_FLUSH );

        substr $out, -4, 4, q[];

        $payload_ref = \$out;
    }

    # head
    my $head = $op + ( $fin ? 128 : 0 );
    $head |= 0b01000000 if $rsv1;
    $head |= 0b00100000 if $rsv2;
    $head |= 0b00010000 if $rsv3;

    my $frame = pack 'C', $head;

    # small payload
    my $len = length $payload_ref->$*;

    if ( $len < 126 ) {
        $frame .= pack 'C', $masked ? ( $len | 128 ) : $len;
    }

    # extended payload (16-bit)
    elsif ( $len < 65536 ) {
        $frame .= pack 'Cn', $masked ? ( 126 | 128 ) : 126, $len;
    }

    # extended payload (64-bit with 32-bit fallback)
    else {
        $frame .= pack 'C', $masked ? ( 127 | 128 ) : 127;

        $frame .= pack( 'Q>', $len );
    }

    # mask payload
    if ($masked) {
        my $mask = pack 'N', int( rand 9 x 7 );

        $payload_ref = \( $mask . to_xor( $payload_ref->$*, $mask ) );
    }

    return $frame . $payload_ref->$*;
}

sub _websocket_parse_frame_header ( $self, $buf_ref ) {
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
## |    3 |                      | Subroutines::ProhibitExcessComplexity                                                                          |
## |      | 109                  | * Subroutine "websocket_listen" with high complexity score (25)                                                |
## |      | 208                  | * Subroutine "_websocket_on_frame" with high complexity score (24)                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 306                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 366, 368             | NamingConventions::ProhibitAmbiguousNames - Ambiguously named variable "second"                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 225                  | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 342                  | ValuesAndExpressions::RequireNumberSeparators - Long number not separated with underscores                     |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 350, 366             | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 454                  | Documentation::RequirePackageMatchesPodName - Pod NAME on line 458 does not match the package declaration      |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
