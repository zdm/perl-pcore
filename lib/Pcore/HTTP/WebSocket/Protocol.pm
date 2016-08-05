package Pcore::HTTP::WebSocket::Protocol;

use Pcore -const, -role;
use Pcore::HTTP::WebSocket::Util;
use Pcore::Util::Text qw[decode_utf8 encode_utf8];
use Compress::Raw::Zlib qw[];

requires qw[websocket_protocol];

has websocket_h => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );
has websocket_max_message_length => ( is => 'ro', isa => PositiveInt, default => 1024 * 1024 * 10 );

# http://www.iana.org/assignments/websocket/websocket.xml#extension-name
# https://tools.ietf.org/html/rfc7692#page-10
has websocket_ext_permessage_deflate => ( is => 'ro', isa => Bool, default => 0 );

has status => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # remote close status

has _msg_op  => ( is => 'ro', isa => Str,      init_arg => undef );
has _msg_buf => ( is => 'ro', isa => ArrayRef, init_arg => undef );

has _ping_callbacks => ( is => 'lazy', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _close_sent => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

sub websocket_listen ($self) {
    $self->websocket_h->on_read(
        sub ($h) {
            if ( my $header = Pcore::HTTP::WebSocket::Util::parse_frame_header( \$h->{rbuf} ) ) {

                # TODO check, that opcode is supported
                # TODO check max. message length
                # TODO check protocol errors
                # TODO process extensions, deflate message
                # TODO dispatch message

                # # check, that opcode is supported by us
                # my $opcode_supported = 0;
                #
                # my $op = $header->{op};
                #
                # if    ( $op == $WS_TEXT )   { $opcode_supported = 1 if $self->{on_text} }
                # elsif ( $op == $WS_BINARY ) { $opcode_supported = 1 if $self->{on_bin} }
                # elsif ( $op == $WS_CONTINUATION || $op == $WS_CLOSE || $op == $WS_PING || $op == $WS_PONG ) { $opcode_supported = 1 }
                #
                # if ( !$opcode_supported ) {
                #
                #     # opcode is not supported
                #     $self->close(1003);
                #
                #     return;
                # }

                # # empty frame
                # if ( !$header->{len} ) {
                #     $self->_on_frame( $header, undef );
                # }
                # else {

                # # disconnect if max frame length is exceeded
                # if ( $header->{len} > $self->{max_frame_length} ) {
                #     $self->close(1009);
                #
                #     return;
                # }

                if ( length $h->{rbuf} >= $header->{len} ) {
                    $self->_on_frame( $header, \substr $h->{rbuf}, 0, $header->{len}, q[] );
                }
                else {
                    $h->unshift_read(
                        chunk => $header->{len},
                        sub ( $h, $data ) {
                            $self->_on_frame( $header, \$data );

                            return;
                        }
                    );
                }

                # }
            }

            return;
        }
    );

    return;
}

sub _on_frame ( $self, $header, $data_ref ) {
    $self->websocket_on_text($data_ref);

    return;
}

# sub _on_frame1 ( $self, $header, $data_ref ) {
#
#     # unmask data
#     $data_ref = \to_xor( $data_ref->$*, $header->{mask} ) if $header->{mask} && $data_ref;
#
#     my $op = $header->{op};
#
#     # process continuation frame
#     if ( !$header->{fin} ) {
#         if ( $op == $WS_CONTINUATION ) {
#
#             # ignore continuation frame, if message was not started
#             if ( !$self->{_msg_op} ) {
#                 undef $self->{_msg_buf};
#
#                 return $self->close(1002);
#             }
#
#             # add continuation frame
#             push $self->{_msg_buf}->@*, $data_ref if $data_ref;
#         }
#         else {
#
#             # start message
#             $self->{_msg_op} = $op;
#
#             push $self->{_msg_buf}->@*, $data_ref if $data_ref;
#         }
#
#         return;
#     }
#
#     my $frames;
#
#     if ( $op == $WS_CONTINUATION ) {
#         if ( !$self->{_msg_op} ) {
#
#             # ignore frame, if message was not started
#             return $self->close(1002);
#         }
#
#         # fin and continuaton frame
#         $op = $self->{_msg_op};
#
#         $frames = $self->{_msg_buf} // [];
#
#         push $frames->@*, $data_ref if $data_ref;
#
#         undef $self->{_msg_op};
#
#         undef $self->{_msg_buf};
#     }
#     else {
#
#         # fin and message frame
#         $frames = [];
#
#         push $frames->@*, $data_ref if $data_ref;
#     }
#
#     # combine frames to single string
#     $data_ref = \join q[], map { $_->$* } $frames->@*;
#
#     # dispatch message
#     if ( $op == $WS_TEXT ) {
#         if ( $self->{on_text} && $data_ref->$* ) {
#             decode_utf8 $data_ref->$*;
#
#             $self->{on_text}->($data_ref);
#         }
#     }
#     elsif ( $op == $WS_BINARY ) {
#         $self->{on_bin}->($data_ref) if $self->{on_bin} && $data_ref->$*;
#     }
#     elsif ( $op == $WS_CLOSE ) {
#         if ( !$self->{status} ) {
#             $self->{status} = $data_ref->$*;
#
#             # send back close op, according to RFC
#             $self->close(1000);
#
#             $self->{on_close}->( $self->{status} ) if $self->{on_close};
#         }
#     }
#     elsif ( $op == $WS_PING ) {
#         $self->h->push_write( _build_frame( 0, 1, 0, 0, 0, $WS_PONG, $data_ref ) );
#     }
#     elsif ( $op == $WS_PONG ) {
#         while ( my $cb = shift $self->{_ping_callbacks}->@* ) {
#             $cb->(1);
#         }
#     }
#     else {
#         $self->close(1003);
#     }
#
#     return;
# }

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    1 | 207                  | Documentation::RequirePackageMatchesPodName - Pod NAME on line 211 does not match the package declaration      |
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
