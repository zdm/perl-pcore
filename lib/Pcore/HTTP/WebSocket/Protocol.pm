package Pcore::HTTP::WebSocket::Protocol;

use Pcore -const, -role;
use Pcore::HTTP::WebSocket::Util qw[:CONST];
use Pcore::Util::Text qw[decode_utf8 encode_utf8];
use Pcore::Util::Data qw[to_xor];
use Compress::Raw::Zlib;

requires qw[websocket_protocol websocket_on_close];

has websocket_max_message_size => ( is => 'ro', isa => PositiveOrZeroInt, default => 1024 * 1024 * 10 );

# http://www.iana.org/assignments/websocket/websocket.xml#extension-name
# https://tools.ietf.org/html/rfc7692#page-10
has websocket_permessage_deflate => ( is => 'ro', isa => Bool, default => 0 );

has _websocket_msg => ( is => 'ro', isa => ArrayRef, init_arg => undef );    # fragmentated message data, [$payload, $op, $rsv1]
has _websocket_deflate => ( is => 'ro', init_arg => undef );
has _websocket_inflate => ( is => 'ro', init_arg => undef );

has _websocket_h => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'], init_arg => undef );
has websocket_close_status => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # close status

sub websocket_listen ($self) {

    # cleanup fragmentated message data
    undef $self->{_websocket_msg};

    $self->{_websocket_h}->on_error(
        sub ( $h, @ ) {
            $self->websocket_on_close(1001) if !$self->{websocket_close_status};               # going away

            return;
        }
    );

    $self->{_websocket_h}->on_read(
        sub ($h) {
            if ( my $header = Pcore::HTTP::WebSocket::Util::parse_frame_header( \$h->{rbuf} ) ) {

                # check protocol errors
                if ( $header->{fin} ) {

                    # this is the last frame of the fragmentated message
                    if ( $header->{op} == $WEBSOCKET_OP_CONTINUATION ) {

                        # message was not started, return 1002 - protocol error
                        return $self->websocket_on_close(1002) if !$self->{_websocket_msg};

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
                        return $self->websocket_on_close(1002) if !$self->{_websocket_msg};

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
                            return $self->websocket_on_close(1009) if $header->{len} + length $self->{_websocket_msg}->[0] > $self->{websocket_max_message_size};
                        }
                        else {
                            return $self->websocket_on_close(1009) if $header->{len} > $self->{websocket_max_message_size};
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

# TODO process ping
sub _websocket_on_frame ( $self, $header, $payload_ref ) {

    # unmask
    $payload_ref = \to_xor( $payload_ref->$*, $header->{mask} ) if $header->{mask} && $payload_ref;

    # decompress
    if ( $header->{rsv1} && $payload_ref ) {
        my $inflate = $self->{_websocket_inflate} ||= Compress::Raw::Zlib::Inflate->new(
            -WindowBits => -15,
            ( $self->{websocket_max_message_size} ? ( -Bufsize => $self->{websocket_max_message_size} ) : () ),
            -AppendOutput => 0,
            -ConsumeInput => 1,
            -LimitOutput  => 1,
        );

        $payload_ref->$* .= "\x00\x00\xff\xff";

        $inflate->inflate( $payload_ref, my $out );

        return $self->websocket_on_close(1009) if length $payload_ref->$*;

        $payload_ref = \$out;
    }

    # this is message fragment frame
    if ( !$header->{fin} ) {

        # add frame to the message buffer
        $self->{_websocket_msg}->[0] .= $payload_ref->$* if $payload_ref;
    }

    # message completed, dispatch message
    else {

        # cleanup fragmentated message data
        undef $self->{_websocket_msg};

        # TODO add buffer, if message is fragmentated

        # dispatch message
        if ( $header->{op} == $WEBSOCKET_OP_TEXT ) {
            decode_utf8 $payload_ref->$*;

            $self->websocket_on_text($payload_ref);
        }
        elsif ( $header->{op} == $WEBSOCKET_OP_BINARY ) {
            $self->websocket_on_binary($payload_ref);
        }
        elsif ( $header->{op} == $WEBSOCKET_OP_CLOSE ) {
            $self->websocket_on_close( $payload_ref->$* );
        }
        elsif ( $header->{op} == $WEBSOCKET_OP_PING ) {

            # send pong
            $self->{_websocket_h}->push_write( $self->_websocket_build_frame( 1, $self->{websocket_permessage_deflate}, 0, 0, $WEBSOCKET_OP_PONG, 9, $payload_ref ) );
        }
        elsif ( $header->{op} == $WEBSOCKET_OP_PONG ) {

            # TODO call ping callbacks
        }
    }

    return;
}

# called, when remote peer close connection
around websocket_on_close => sub ( $orig, $self, $status ) {

    # connection already closed
    return if $self->{websocket_close_status};

    # close connection
    $self->websocket_close($status);

    # call original on_close method
    $self->$orig($status);

    return;
};

# METHODS
sub websocket_close ( $self, $status ) {

    # connection already closed
    return if $self->{websocket_close_status};

    # mark connection as closed
    $self->{websocket_close_status} = $status;

    # cleanup fragmentated message data
    undef $self->{_websocket_msg};

    # send close message
    $self->{_websocket_h}->push_write( $self->_websocket_build_frame( 1, $self->{websocket_permessage_deflate}, 0, 0, $WEBSOCKET_OP_CLOSE, 0, \$status ) );

    # destroy handle
    $self->{_websocket_h}->destroy;

    return;
}

sub websocket_send_text ( $self, $payload ) {
    $self->{_websocket_h}->push_write( $self->_websocket_build_frame( 1, $self->{websocket_permessage_deflate}, 0, 0, $WEBSOCKET_OP_TEXT, 0, \encode_utf8 $payload) );

    return;
}

sub websocket_send_binary ( $self, $payload ) {
    $self->{_websocket_h}->push_write( $self->_websocket_build_frame( 1, $self->{websocket_permessage_deflate}, 0, 0, $WEBSOCKET_OP_BINARY, 0, \$payload ) );

    return;
}

# TODO
sub websocket_ping ($self) {
    my $payload = time;

    $self->{_websocket_h}->push_write( $self->_websocket_build_frame( 1, $self->{websocket_permessage_deflate}, 0, 0, $WEBSOCKET_OP_PING, 0, \$payload ) );

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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 24                   | Subroutines::ProhibitExcessComplexity - Subroutine "websocket_listen" with high complexity score (25)          |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 246                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 139                  | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 282                  | ValuesAndExpressions::RequireNumberSeparators - Long number not separated with underscores                     |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 290                  | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 325                  | Documentation::RequirePackageMatchesPodName - Pod NAME on line 329 does not match the package declaration      |
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
