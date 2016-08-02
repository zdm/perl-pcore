package Pcore::App::Controller::WebSocket;

use Pcore -role;
use Digest::SHA1 qw[];

with qw[Pcore::App::Controller];

# https://learn.javascript.ru/websockets

sub run ($self) {
    my $h = $self->req->_h;

    # "HTTP_SEC_WEBSOCKET_EXTENSIONS" => "permessage-deflate" # ASCII, bytes::len = 18,

    # say dump $self->req->env;

    my $ac = P->data->to_b64( Digest::SHA1::sha1( $self->req->env->{HTTP_SEC_WEBSOCKET_KEY} . '258EAFA5-E914-47DA-95CA-C5AB0DC85B11' ) );
    $ac =~ s/\n//smg;

    # HTTP_SEC_WEBSOCKET_VERSION 13 handshake
    $self->req->write(
        101,
        [   Upgrade                => 'WebSocket',
            Connection             => 'Upgrade',
            'Sec-WebSocket-Accept' => $ac,

            # 'WebSocket-Origin'     => 'http://127.0.0.1:80/',
            # 'WebSocket-Location'   => 'ws://127.0.0.1:80/websocket/',
        ]
    );

    $self->req->{_response_status} = $Pcore::HTTP::Server::Request::HTTP_SERVER_RESPONSE_FINISHED;

    say 'CONNECTED';

    our $ff = $h;

    $h->on_read(
        sub ($h1) {
            say 'ON_READ: ', dump $h->rbuf;

            return;
        }
    );

    $h->on_error(
        sub {
            say $_[2];

            return;
        }
    );

    for ( 1 .. 10 ) {
        $self->write_text( $h, 'мама' );
    }

    return;
}

sub write_text ( $self, $h, $data ) {
    my $frame = [ 1, 0, 0, 0, 0x1, P->text->encode_utf8($data) ];

    use Compress::Raw::Zlib;

    my $deflate = Compress::Raw::Zlib::Deflate->new(
        AppendOutput => 1,
        MemLevel     => 8,
        WindowBits   => -15
    );

    $deflate->deflate( $frame->[5], my $out );

    $deflate->flush( $out, Z_SYNC_FLUSH );

    # $frame->@[ 1, 5 ] = ( 1, substr( $out, 0, length($out) - 4 ) );

    my $b = $self->build_frame( 0, $frame->@* );    # P->text->encode_utf8($data)

    $h->push_write($b);

    return;
}

sub build_frame ( $self, $masked, $fin, $rsv1, $rsv2, $rsv3, $op, $payload ) {

    # Head
    my $head = $op + ( $fin ? 128 : 0 );
    $head |= 0b01000000 if $rsv1;
    $head |= 0b00100000 if $rsv2;
    $head |= 0b00010000 if $rsv3;
    my $frame = pack 'C', $head;

    # Small payload
    my $len = length $payload;

    if ( $len < 126 ) {
        $frame .= pack 'C', $masked ? ( $len | 128 ) : $len;
    }

    # Extended payload (16-bit)
    elsif ( $len < 65536 ) {
        $frame .= pack 'Cn', $masked ? ( 126 | 128 ) : 126, $len;
    }

    # Extended payload (64-bit with 32-bit fallback)
    else {
        $frame .= pack 'C', $masked ? ( 127 | 128 ) : 127;

        $frame .= pack( 'Q>', $len );
    }

    # Mask payload
    if ($masked) {
        my $mask = pack 'N', int( rand 9 x 7 );

        $payload = $mask . xor_encode( $payload, $mask x 128 );
    }

    return $frame . $payload;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 11                   | Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 85                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 102                  | ValuesAndExpressions::RequireNumberSeparators - Long number not separated with underscores                     |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 110                  | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
