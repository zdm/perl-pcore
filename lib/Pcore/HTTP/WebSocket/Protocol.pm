package Pcore::HTTP::WebSocket::Protocol;

use Pcore -const, -role;
use Pcore::HTTP::WebSocket::Util qw[:CONST];
use Pcore::Util::Text qw[decode_utf8 encode_utf8];
use Pcore::Util::Text qw[decode_utf8];
use Pcore::Util::Data qw[to_xor];
use Compress::Raw::Zlib qw[];

requires qw[websocket_protocol websocket_on_close];

has websocket_h => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );
has websocket_max_message_size => ( is => 'ro', isa => PositiveOrZeroInt, default => 1024 * 1024 * 10 );

# http://www.iana.org/assignments/websocket/websocket.xml#extension-name
# https://tools.ietf.org/html/rfc7692#page-10
has websocket_ext_permessage_deflate => ( is => 'ro', isa => Bool, default => 0 );

has _websocket_msg_op                 => ( is => 'ro', isa => Str,      init_arg => undef );
has _websocket_msg_permessage_deflate => ( is => 'ro', isa => Bool,     init_arg => undef );
has _websocket_msg_buf                => ( is => 'ro', isa => ArrayRef, init_arg => undef );    # buffer for fragmentated message payload

has status => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );                     # remote close status

has _ping_callbacks => ( is => 'lazy', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _close_sent => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

# TODO install on_error callback
sub websocket_listen ($self) {

    # cleanup buffers
    $self->{_websocket_msg_op}                 = undef;
    $self->{_websocket_msg_permessage_deflate} = 0;
    $self->{_websocket_msg_buf}                = q[];

    $self->websocket_h->on_read(
        sub ($h) {
            if ( my $header = Pcore::HTTP::WebSocket::Util::parse_frame_header( \$h->{rbuf} ) ) {

                # check protocol errors
                if ( $header->{fin} ) {

                    # this is the last frame of fragmentated message
                    if ( $header->{op} == $WEBSOCKET_OP_CONTINUATION ) {

                        # message was not started, return 1002 - protocol error
                        return $self->websocket_close(1002) if ( !$self->{_websocket_msg_op} );

                        # restore message "op"
                        $header->{op} = $self->{_websocket_msg_op};

                        # restore "permessage_deflate" flag
                        $header->{permessage_deflate} = $self->{_websocket_msg_permessage_deflate};
                    }

                    # this is the single-frame message
                    else {

                        # set "permessage_deflate" flag
                        $header->{permessage_deflate} = $self->{websocket_ext_permessage_deflate} && $header->{rsv1} ? 1 : 0;
                    }
                }
                else {

                    # this is the next frame of fragmentated message
                    if ( $header->{op} == $WEBSOCKET_OP_CONTINUATION ) {

                        # message was not started, return 1002 - protocol error
                        return $self->websocket_close(1002) if ( !$self->{_websocket_msg_op} );

                        # restore "permessage_deflate" flag
                        $header->{permessage_deflate} = $self->{_websocket_msg_permessage_deflate};
                    }

                    # this is the first frame of the fragmentated message
                    else {

                        # store message "op"
                        $self->{_websocket_msg_op} = $header->{op};

                        # set and store "permessage_deflate" flag
                        $self->{_websocket_msg_op} = $header->{permessage_deflate} = $self->{websocket_ext_permessage_deflate} && $header->{rsv1} ? 1 : 0;
                    }
                }

                # check max. message size, return 1009 - message too big
                # TODO check for decompressed frame payload
                return $self->websocket_close(1009) if $self->{websocket_max_message_size} && ( $header->{len} + length $self->{_websocket_msg_buf} ) > $self->{websocket_max_message_size};

                # empty frame
                if ( !$header->{len} ) {
                    $self->_on_frame( $header, undef );
                }
                elsif ( length $h->{rbuf} >= $header->{len} ) {
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

            return;
        }
    );

    return;
}

sub _websocket_on_frame ( $self, $header, $payload_ref ) {

    # unmask
    $payload_ref = \to_xor( $payload_ref->$*, $header->{mask} ) if $header->{mask} && $payload_ref;

    # decompress
    if ( $header->{permessage_deflate} && $payload_ref ) {
        my $inflate = $self->{inflate} ||= Compress::Raw::Zlib::Inflate->new(
            Bufsize     => $self->{websocket_max_message_size},
            LimitOutput => 1,
            WindowBits  => -15
        );

        $payload_ref->$* .= "\x00\x00\xff\xff";

        $inflate->inflate( $payload_ref->$*, my $out );

        return $self->websocket_close(1009) if length $payload_ref->$*;

        $payload_ref = \$out;
    }

    # this is message fragment frame
    if ( !$header->{fin} ) {

        # add frame to the message buffer
        $self->{_websocket_msg_buf} .= $payload_ref->$* if $payload_ref;
    }

    # message complete, dispatch message
    else {

        # cleanup buffers
        $self->{_websocket_msg_op}                 = undef;
        $self->{_websocket_msg_permessage_deflate} = 0;
        $self->{_websocket_msg_buf}                = q[];

        $self->websocket_on_text($payload_ref);
    }

    return;
}

sub websocket_close ( $self, $status ) {

    # cleanup buffers
    $self->{_websocket_msg_op}                 = undef;
    $self->{_websocket_msg_permessage_deflate} = 0;
    $self->{_websocket_msg_buf}                = q[];

    return;
}

sub websocket_send_text {

    # my $deflate = $self->{deflate} ||= Compress::Raw::Zlib::Deflate->new(
    #     AppendOutput => 1,
    #     MemLevel     => 8,
    #     WindowBits   => -15
    # );
    #
    # $deflate->deflate( $frame->[5], my $out );
    #
    # $deflate->flush( $out, Z_SYNC_FLUSH );
    #
    # @$frame[ 1, 5 ] = ( 1, substr( $out, 0, length($out) - 4 ) );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 129                  | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 200                  | Documentation::RequirePackageMatchesPodName - Pod NAME on line 204 does not match the package declaration      |
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
