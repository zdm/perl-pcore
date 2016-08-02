package Pcore::API::WebSocket;

use Pcore -class, -const;
use Pcore::AE::Handle;
use Pcore::Util::Text qw[decode_utf8];
use Compress::Raw::Zlib;

has h => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );
has max_frame_length => ( is => 'ro', isa => PositiveInt, default => 1024 * 1024 * 10 );

has on_text  => ( is => 'ro', isa => Maybe [CodeRef] );
has on_bin   => ( is => 'ro', isa => Maybe [CodeRef] );
has on_close => ( is => 'ro', isa => Maybe [CodeRef] );

has _msg_op         => ( is => 'ro',   isa => Str,      init_arg => undef );
has _msg_buf        => ( is => 'ro',   isa => ArrayRef, init_arg => undef );
has _ping_callbacks => ( is => 'lazy', isa => ArrayRef, default  => sub { [] }, init_arg => undef );
has _close_sent => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );
has status      => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # remote close status

const our $WS_GUID => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

const our $WS_CONTINUATION => 0x0;
const our $WS_TEXT         => 0x1;
const our $WS_BINARY       => 0x2;
const our $WS_CLOSE        => 0x8;
const our $WS_PING         => 0x9;
const our $WS_PONG         => 0xa;

const our $WS_CLOSE_NORMAL          => 1000;                                        # normal close
const our $WS_CLOSE_GONE            => 1001;                                        # удалённая сторона «исчезла». Например, процесс сервера убит или браузер перешёл на другую страницу
const our $WS_CLOSE_PROTOCOL_ERROR  => 1002;                                        # protocol error
const our $WS_CLOSE_INVALID_OPCODE  => 1003;                                        # unsupported message opcode
const our $WS_CLOSE_FRAME_TOO_LARGE => 1010;

# TODO process handle on_error callback

sub DEMOLISH ( $self, $global ) {
    $self->close($WS_CLOSE_GONE) if !$global;

    return;
}

# TODO
sub connect ( $self, $url, @ ) {                                                    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    my %args = (
        on_error        => undef,
        on_connect      => undef,
        connect_timeout => 30,
        splice @_, 2
    );

    Pcore::AE::Handle->new(
        %args,
        connect => $url,
        on_error => sub ( $h, @ ) {
            say 'ERRRO';

            return;
        },
        on_connect => sub ( $h, @ ) {

            # TODO generate key

            $h->push_write("GET / HTTP/1.1\r\nUpgrade:websocket\r\nConnection:upgrade\r\nSec-WebSocket-Key:123\r\nSec-WebSocket-Version:13\r\nSec-WebSocket-Extensions:deflate-frame\r\nSec-WebSocket-Protocol:soap, wamp\r\n\r\n");

            $h->read_http_res_headers(
                headers => 1,
                sub ( $h1, $res, $error ) {
                    $self->{h} = $h;

                    $self->listen;

                    $args{on_connect}->($self);

                    return;
                }
            );

            return;
        }
    );

    return $self;
}

sub listen ($self) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    $self->h->on_read(
        sub ($h) {
            if ( my $header = _parse_frame_header( \$h->{rbuf} ) ) {

                # check, that opcode is supported by us
                my $opcode_supported = 0;

                my $op = $header->{op};

                if    ( $op == $WS_TEXT )   { $opcode_supported = 1 if $self->{on_text} }
                elsif ( $op == $WS_BINARY ) { $opcode_supported = 1 if $self->{on_bin} }
                elsif ( $op == $WS_CONTINUATION || $op == $WS_CLOSE || $op == $WS_PING || $op == $WS_PONG ) { $opcode_supported = 1 }

                if ( !$opcode_supported ) {

                    # opcode is not supported
                    $self->close($WS_CLOSE_INVALID_OPCODE);

                    return;
                }

                # empty frame
                if ( !$header->{len} ) {
                    $self->_on_frame( $header, undef );
                }
                else {

                    # disconnect if max frame length is exceeded
                    if ( $header->{len} > $self->{max_frame_length} ) {
                        $self->close($WS_CLOSE_FRAME_TOO_LARGE);

                        return;
                    }

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
                }
            }

            return;
        }
    );

    return $self;
}

sub _on_frame ( $self, $header, $data_ref ) {

    # unmask data
    $data_ref = _xor_encode( $data_ref, $header->{mask} ) if $header->{mask} && $data_ref;

    my $op = $header->{op};

    # process continuation frame
    if ( !$header->{fin} ) {
        if ( $op == $WS_CONTINUATION ) {

            # ignore continuation frame, if message was not started
            if ( !$self->{_msg_op} ) {
                undef $self->{_msg_buf};

                return $self->close($WS_CLOSE_PROTOCOL_ERROR);
            }

            # add continuation frame
            push $self->{_msg_buf}->@*, $data_ref if $data_ref;
        }
        else {

            # start message
            $self->{_msg_op} = $op;

            push $self->{_msg_buf}->@*, $data_ref if $data_ref;
        }

        return;
    }

    my $frames;

    if ( $op == $WS_CONTINUATION ) {
        if ( !$self->{_msg_op} ) {

            # ignore frame, if message was not started
            return $self->close($WS_CLOSE_PROTOCOL_ERROR);
        }

        # fin and continuaton frame
        $op = $self->{_msg_op};

        $frames = $self->{_msg_buf} // [];

        push $frames->@*, $data_ref if $data_ref;

        undef $self->{_msg_op};

        undef $self->{_msg_buf};
    }
    else {

        # fin and message frame
        $frames = [];

        push $frames->@*, $data_ref if $data_ref;
    }

    # combine frames to single string
    $data_ref = \join q[], map { $_->$* } $frames->@*;

    # dispatch message
    if ( $op == $WS_TEXT ) {
        if ( $self->{on_text} && $data_ref->$* ) {
            decode_utf8 $data_ref->$*;

            $self->{on_text}->($data_ref);
        }
    }
    elsif ( $op == $WS_BINARY ) {
        $self->{on_bin}->($data_ref) if $self->{on_bin} && $data_ref->$*;
    }
    elsif ( $op == $WS_CLOSE ) {
        if ( !$self->{status} ) {
            $self->{status} = $data_ref->$*;

            # send back close op, according to RFC
            $self->close($WS_CLOSE_NORMAL);

            $self->{on_close}->( $self->{status} ) if $self->{on_close};
        }
    }
    elsif ( $op == $WS_PING ) {
        $self->h->push_write( _build_frame( 0, 1, 0, 0, 0, $WS_PONG, $data_ref ) );
    }
    elsif ( $op == $WS_PONG ) {
        while ( my $cb = shift $self->{_ping_callbacks}->@* ) {
            $cb->(1);
        }
    }
    else {
        $self->close($WS_CLOSE_INVALID_OPCODE);
    }

    return;
}

sub close ( $self, $status = $WS_CLOSE_NORMAL ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    return if $self->{_close_sent};

    $self->{_close_sent} = $status;

    $self->h->push_write( _build_frame( 0, 1, 0, 0, 0, $WS_CLOSE, \$status ) );

    # close connection if error is fatal
    $self->h->destroy if $status != $WS_CLOSE_NORMAL;

    return;
}

sub ping ( $self, $cb ) {
    push $self->_ping_callbacks->@*, $cb;

    return if $self->_ping_callbacks->@* > 1;

    $self->h->push_write( _build_frame( 0, 1, 0, 0, 0, $WS_PING, \time ) );

    return;
}

sub send_text ( $self, $data ) {

    # my $deflate = Compress::Raw::Zlib::Deflate->new(
    #     AppendOutput => 1,
    #     MemLevel     => 8,
    #     WindowBits   => -15
    # );
    #
    # $deflate->deflate( $frame->[5], my $out );
    #
    # $deflate->flush( $out, Z_SYNC_FLUSH );
    #
    # $frame->@[ 1, 5 ] = ( 1, substr( $out, 0, length($out) - 4 ) );

    $self->h->push_write( _build_frame( 0, 1, 0, 0, 0, $WS_TEXT, \P->text->encode_utf8($data) ) );

    return;
}

sub send_bin ( $self, $data ) {

    # my $deflate = Compress::Raw::Zlib::Deflate->new(
    #     AppendOutput => 1,
    #     MemLevel     => 8,
    #     WindowBits   => -15
    # );
    #
    # $deflate->deflate( $frame->[5], my $out );
    #
    # $deflate->flush( $out, Z_SYNC_FLUSH );
    #
    # $frame->@[ 1, 5 ] = ( 1, substr( $out, 0, length($out) - 4 ) );

    $self->h->push_write( _build_frame( 0, 1, 0, 0, 0, $WS_BINARY, \$data ) );

    return;
}

# stolen directly from Mojo::WebSocket
sub _build_frame ( $masked, $fin, $rsv1, $rsv2, $rsv3, $op, $data_ref ) {

    # head
    my $head = $op + ( $fin ? 128 : 0 );
    $head |= 0b01000000 if $rsv1;
    $head |= 0b00100000 if $rsv2;
    $head |= 0b00010000 if $rsv3;

    my $frame = pack 'C', $head;

    # small payload
    my $len = length $data_ref->$*;

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

        $data_ref = \( $mask . _xor_encode( $data_ref, $mask ) );
    }

    return $frame . $data_ref->$*;
}

sub _parse_frame_header ( $buf_ref ) {
    return unless length $buf_ref->$* >= 2;

    my ( $first, $second ) = unpack 'C*', substr( $buf_ref->$*, 0, 2 );

    my $masked = $second & 0b10000000;

    my $res;

    ( my $hlen, $res->{len} ) = ( 2, $second & 0b01111111 );

    # small payload
    if ( $res->{len} < 126 ) {
        $hlen += 4 if $masked;

        return if length $buf_ref->$* < $hlen;

        # cut header
        my $header = substr $buf_ref->$*, 0, $hlen, q[];

        $res->{mask} = substr $header, 2, 4, q[] if $masked;
    }

    # extended payload (16-bit)
    elsif ( $res->{len} == 126 ) {
        $hlen = $masked ? 8 : 4;

        return if length $buf_ref->$* < $hlen;

        # cut header
        my $header = substr $buf_ref->$*, 0, $hlen, q[];

        $res->{mask} = substr $header, 4, 4, q[] if $masked;

        $res->{len} = unpack 'n', substr $header, 2, 2, q[];
    }

    # extended payload (64-bit with 32-bit fallback)
    elsif ( $res->{len} == 127 ) {
        $hlen = $masked ? 10 : 14;

        return if length $buf_ref->$* < $hlen;

        # cut header
        my $header = substr $buf_ref->$*, 0, 10, q[];

        $res->{mask} = substr $header, 10, 4, q[] if $masked;

        $res->{len} = unpack 'Q>', substr $header, 2, 8, q[];
    }

    # FIN
    $res->{fin} = ( $first & 0b10000000 ) == 0b10000000 ? 1 : 0;

    # RSV1-3
    $res->{rsv1} = ( $first & 0b01000000 ) == 0b01000000 ? 1 : 0;
    $res->{rsv2} = ( $first & 0b00100000 ) == 0b00100000 ? 1 : 0;
    $res->{rsv3} = ( $first & 0b00010000 ) == 0b00010000 ? 1 : 0;

    # opcode
    $res->{op} = $first & 0b00001111;

    return $res;
}

sub _xor_encode ( $data_ref, $mask ) {
    no feature qw[bitwise];

    $mask = $mask x 128;

    my $len = length $mask;

    my $buffer = my $output = q[];

    $output .= $buffer ^ $mask while length( $buffer = substr( $data_ref->$*, 0, $len, q[] ) ) == $len;

    $output .= $buffer ^ substr( $mask, 0, length $buffer, q[] );

    return \$output;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 145                  | Subroutines::ProhibitExcessComplexity - Subroutine "_on_frame" with high complexity score (27)                 |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 |                      | NamingConventions::ProhibitAmbiguousNames                                                                      |
## |      | 244                  | * Ambiguously named subroutine "close"                                                                         |
## |      | 348, 350             | * Ambiguously named variable "second"                                                                          |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 306                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 346                  | ControlStructures::ProhibitNegativeExpressionsInUnlessAndUntilConditions - Found ">=" in condition for an      |
## |      |                      | "unless"                                                                                                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 324                  | ValuesAndExpressions::RequireNumberSeparators - Long number not separated with underscores                     |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 419                  | ControlStructures::ProhibitPostfixControls - Postfix control "while" used                                      |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 46                   | CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 332, 348, 419, 421   | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::WebSocket

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
