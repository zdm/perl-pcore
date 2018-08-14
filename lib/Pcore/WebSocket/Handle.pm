package Pcore::WebSocket::Handle;

use Pcore -const, -role, -res;
use Pcore::Util::Scalar qw[is_ref weaken];
use Pcore::Util::Text qw[decode_utf8 encode_utf8];
use Pcore::Util::UUID qw[uuid_v1mc_str];
use Pcore::Util::Data qw[to_b64 to_xor];
use Pcore::Util::Digest qw[sha1];
use Compress::Raw::Zlib;

# Websocket v13 spec. https://tools.ietf.org/html/rfc6455

# compression:
# http://www.iana.org/assignments/websocket/websocket.xml#extension-name
# https://tools.ietf.org/html/rfc7692#page-10
# https://www.igvita.com/2013/11/27/configuring-and-optimizing-websocket-compression/

requires qw[_on_connect _on_disconnect _on_text _on_binary];

has max_message_size => 1_024 * 1_024 * 100;    # PositiveOrZeroInt, 0 - do not check message size
has compression      => ();                     # Bool, use permessage_deflate compression
has pong_timeout     => ();                     # send pong on inactive connection
has on_ping          => ();                     # Maybe [CodeRef], ($self, \$payload)
has on_pong          => ();                     # Maybe [CodeRef], ($self, \$payload)

has id           => sub {uuid_v1mc_str};
has is_connected => ();                         # Bool
has _connect     => ();                         # prepared connect data
has _is_client   => ();
has _h           => ();                         # InstanceOf ['Pcore::AE::Handle']
has _compression => ();                         # Bool, use compression, set after connected
has _send_masked => ();                         # Bool, mask data on send, for websocket client only
has _deflate     => ();
has _inflate     => ();

const our $WEBSOCKET_VERSION => 13;
const our $WEBSOCKET_GUID    => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

const our $WEBSOCKET_PING_PONG_PAYLOAD => "\xFF";

# http://www.iana.org/assignments/websocket/websocket.xml#opcode
const our $WEBSOCKET_OP_CONTINUATION => 0;
const our $WEBSOCKET_OP_TEXT         => 1;
const our $WEBSOCKET_OP_BINARY       => 2;
const our $WEBSOCKET_OP_CLOSE        => 8;
const our $WEBSOCKET_OP_PING         => 9;
const our $WEBSOCKET_OP_PONG         => 10;

# http://www.iana.org/assignments/websocket/websocket.xml#close-code-number
const our $WEBSOCKET_STATUS_REASON => {
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

our $SERVER_CONN;

sub DESTROY ( $self ) {
    if ( ${^GLOBAL_PHASE} ne 'DESTRUCT' ) {
        $self->disconnect( res [ 1001, $WEBSOCKET_STATUS_REASON ] );
    }

    return;
}

sub accept ( $self, $req ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    my $env = $req->{env};

    # websocket version is not specified or not supported
    if ( !$env->{HTTP_SEC_WEBSOCKET_VERSION} || $env->{HTTP_SEC_WEBSOCKET_VERSION} ne $WEBSOCKET_VERSION ) {
        $req->return_xxx(400);

        return;
    }

    # websocket key is not specified
    if ( !$env->{HTTP_SEC_WEBSOCKET_KEY} ) {
        $req->return_xxx(400);

        return;
    }

    my $protocol = do {
        no strict qw[refs];

        ${ ref($self) . '::PROTOCOL' };
    };

    # check websocket protocol
    if ($protocol) {
        if ( !$env->{HTTP_SEC_WEBSOCKET_PROTOCOL} || $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} !~ /\b$protocol\b/smi ) {
            $req->return_xxx(400);

            return;
        }
    }
    elsif ( $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} ) {
        $req->return_xxx(400);

        return;
    }

    # server send unmasked frames
    $self->{_send_masked} = 0;

    # drop compression
    $self->{_compression} = 0;

    # create response headers
    my @headers = (    #
        'Sec-WebSocket-Accept' => $self->_get_challenge( $env->{HTTP_SEC_WEBSOCKET_KEY} ),
        ( $protocol ? ( 'Sec-WebSocket-Protocol' => $protocol ) : () ),
    );

    # check and set extensions
    if ( $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} ) {

        # use compression, if server and client support compression
        if ( $self->{compression} && $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} =~ /\bpermessage-deflate\b/smi ) {
            $self->{_compression} = 1;

            push @headers, ( 'Sec-WebSocket-Extensions' => 'permessage-deflate' );
        }
    }

    # accept websocket connection
    my $h = $req->accept_websocket( \@headers );

    # store connestion
    $SERVER_CONN->{ $self->{id} } = $self;

    # start listen
    $self->__on_connect($h);

    return 1;
}

# TODO store connection args for reconnect???
sub connect ( $self, $uri, %args ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    my $protocol = do {
        no strict qw[refs];

        ${ ref($self) . '::PROTOCOL' };
    };

    $self->{_is_client}   = 1;
    $self->{_send_masked} = 1;          # client always send masked data

    if ( $uri =~ m[\Awss?://unix:(.+)?/]sm ) {
        $self->{_connect} = [ 'unix/', $1 ];

        $uri = P->uri($uri) if !is_ref $uri;
    }
    elsif ( $uri =~ m[\A(wss?)://[*]:(.+)]sm ) {
        $uri = P->uri("$1://127.0.0.1:$2");

        $self->{_connect} = $uri;
    }
    else {
        $uri = P->uri($uri) if !is_ref $uri;

        $self->{_connect} = $uri;
    }

    my $h = P->handle(
        $self->{_connect},
        timeout         => undef,
        connect_timeout => $args{connect_timeout},
        tls_ctx         => $args{tls_ctx},
        bind_ip         => $args{bind_ip},
    );

    # connection error
    if ( !$h ) {
        $self->_on_disconnect( res [ $h->{status}, $h->{reason} ] );

        return;
    }

    # start TLS, only if TLS is required and TLS is not established yet
    $h->starttls if $uri->is_secure && !exists $h->{tls};

    # TLS error
    if ( !$h ) {
        $self->_on_disconnect( res [ $h->{status}, $h->{reason} ] );

        return;
    }

    # generate websocket key
    my $sec_websocket_key = to_b64 rand 100_000, q[];

    my $request_path = $uri->path->to_uri . ( $uri->query ? q[?] . $uri->query : q[] );

    my @headers = (    #
        "GET $request_path HTTP/1.1",
        'Host:' . $uri->host,
        "User-Agent:Pcore-HTTP/$Pcore::VERSION",
        'Upgrade:websocket',
        'Connection:upgrade',
        "Sec-WebSocket-Version:$Pcore::WebSocket::Handle::WEBSOCKET_VERSION",
        "Sec-WebSocket-Key:$sec_websocket_key",
        ( $protocol            ? "Sec-WebSocket-Protocol:$protocol"            : () ),
        ( $self->{compression} ? 'Sec-WebSocket-Extensions:permessage-deflate' : () ),
    );

    # write headers
    $h->write( join( $CRLF, @headers ) . $CRLF . $CRLF );

    # write headers error
    if ( !$h ) {
        $self->_on_disconnect( res [ $h->{status}, $h->{reason} ] );

        return;
    }

    # read response headers
    my $headers = $h->read_http_res_headers;

    # read headers error
    if ( !$h ) {
        $self->_on_disconnect( res [ $h->{status}, $h->{reason} ] );

        return;
    }

    my $res_headers = $headers->{headers};

    # check response status
    if ( $headers->{status} != 101 ) {
        $self->_on_disconnect( res [ $Pcore::Handle::HANDLE_STATUS_PROTOCOL_ERROR, 'Invalid HTTP headers' ] );

        return;
    }

    # check response connection headers
    if ( !$res_headers->{CONNECTION} || !$res_headers->{UPGRADE} || $res_headers->{CONNECTION} !~ /\bupgrade\b/smi || $res_headers->{UPGRADE} !~ /\bwebsocket\b/smi ) {
        $self->_on_disconnect( res [ $Pcore::Handle::HANDLE_STATUS_PROTOCOL_ERROR, q[WebSocket handshake error] ] );

        return;
    }

    # validate SEC_WEBSOCKET_ACCEPT
    if ( !$res_headers->{SEC_WEBSOCKET_ACCEPT} || $res_headers->{SEC_WEBSOCKET_ACCEPT} ne $self->_get_challenge($sec_websocket_key) ) {
        $self->_on_disconnect( res [ $Pcore::Handle::HANDLE_STATUS_PROTOCOL_ERROR, q[Invalid SEC_WEBSOCKET_ACCEPT header] ] );

        return;
    }

    # check protocol
    if ( $res_headers->{SEC_WEBSOCKET_PROTOCOL} ) {
        if ( !$protocol || $res_headers->{SEC_WEBSOCKET_PROTOCOL} !~ /\b$protocol\b/smi ) {
            $self->_on_disconnect( res [ $Pcore::Handle::HANDLE_STATUS_PROTOCOL_ERROR, qq[WebSocket server returned unsupported protocol "$res_headers->{SEC_WEBSOCKET_PROTOCOL}"] ] );

            return;
        }
    }
    elsif ($protocol) {
        $self->_on_disconnect( res [ $Pcore::Handle::HANDLE_STATUS_PROTOCOL_ERROR, q[WebSocket server returned no protocol] ] );

        return;
    }

    # drop compression
    $self->{_compression} = 0;

    # check compression support
    if ( $res_headers->{SEC_WEBSOCKET_EXTENSIONS} ) {

        # use compression, if server and client support compression
        if ( $self->{compression} && $res_headers->{SEC_WEBSOCKET_EXTENSIONS} =~ /\bpermessage-deflate\b/smi ) {
            $self->{_compression} = 1;
        }
    }

    # call protocol on_connect
    $self->__on_connect($h);

    return;
}

sub send_text ( $self, $data_ref ) {
    $self->{_h}->write( $self->_build_frame( 1, $self->{_compression}, 0, 0, $WEBSOCKET_OP_TEXT, $data_ref ) );

    return;
}

sub send_binary ( $self, $data_ref ) {
    $self->{_h}->write( $self->_build_frame( 1, $self->{_compression}, 0, 0, $WEBSOCKET_OP_BINARY, $data_ref ) );

    return;
}

sub send_ping ( $self, $payload = $WEBSOCKET_PING_PONG_PAYLOAD ) {
    $self->{_h}->write( $self->_build_frame( 1, 0, 0, 0, $WEBSOCKET_OP_PING, \$payload ) );

    return;
}

sub send_pong ( $self, $payload = $WEBSOCKET_PING_PONG_PAYLOAD ) {
    $self->{_h}->write( $self->_build_frame( 1, 0, 0, 0, $WEBSOCKET_OP_PONG, \$payload ) );

    return;
}

# TODO
sub disconnect ( $self, $status = undef ) {
    return if !$self->{is_connected};

    # mark connection as closed
    $self->{is_connected} = 0;

    $status = res [ 1000, $WEBSOCKET_STATUS_REASON ] if !defined $status;

    # send close message
    # $self->{_h}->write( $self->_build_frame( 1, 0, 0, 0, $WEBSOCKET_OP_CLOSE, \( pack( 'n', $status->{status} ) . encode_utf8 $status->{reason} ) ) );

    # destroy handle
    $self->{_h}->shutdown;

    # remove from conn, on server only
    delete $SERVER_CONN->{ $self->{id} } if !$self->{_is_client};

    # call protocol on_disconnect
    $self->_on_disconnect($status);

    return;
}

# UTILS
sub _get_challenge ( $self, $key ) {
    return to_b64( sha1( ($key) . $WEBSOCKET_GUID ), q[] );
}

sub _build_frame ( $self, $fin, $rsv1, $rsv2, $rsv3, $op, $payload_ref ) {
    my $masked = $self->{_send_masked};

    # deflate
    if ($rsv1) {
        my $deflate = $self->{_deflate} ||= Compress::Raw::Zlib::Deflate->new(
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
    elsif ( $len < 65_536 ) {
        $frame .= pack 'Cn', $masked ? ( 126 | 128 ) : 126, $len;
    }

    # extended payload (64-bit with 32-bit fallback)
    else {
        $frame .= pack 'C', $masked ? ( 127 | 128 ) : 127;

        $frame .= pack 'Q>', $len;
    }

    # mask payload
    if ($masked) {
        my $mask = pack 'N', int rand 4_294_967_295;

        $payload_ref = \( $mask . to_xor( $payload_ref->$*, $mask ) );
    }

    return $frame . $payload_ref->$*;
}

# TODO $self is undef, on_error, pong_timeout
sub __on_connect ( $self, $h ) {
    return if $self->{is_connected};

    $self->{is_connected} = 1;

    $self->{_h} = $h;

    weaken $self;

    # set on_error handler
    # $self->{_h}->on_error(
    #     sub ( $h, @ ) {
    #         $self->disconnect( res [ 1001, $WEBSOCKET_STATUS_REASON ] ) if $self;    # 1001 - Going Away

    #         return;
    #     }
    # );

    # start listen
    Coro::async_pool {
        my $msg;

        while () {
            my $header = _parse_frame_header($h);

            last if !$header;
            last if !$self;

            # check protocol errors
            if ( $header->{fin} ) {

                # this is the last frame of the fragmented message
                if ( $header->{op} == $WEBSOCKET_OP_CONTINUATION ) {

                    # message was not started, return 1002 - protocol error
                    return $self->disconnect( res [ 1002, $WEBSOCKET_STATUS_REASON ] ) if !$msg;

                    # restore message "op", "rsv1"
                    ( $header->{op}, $header->{rsv1} ) = ( $msg->[1], $msg->[2] );
                }
            }
            else {

                # this is the next frame of the fragmented message
                if ( $header->{op} == $WEBSOCKET_OP_CONTINUATION ) {

                    # message was not started, return 1002 - protocol error
                    return $self->disconnect( res [ 1002, $WEBSOCKET_STATUS_REASON ] ) if !$msg;

                    # restore "rsv1" flag
                    $header->{rsv1} = $msg->[2];
                }

                # this is the first frame of the fragmented message
                else {

                    # store message "op"
                    $msg->[1] = $header->{op};

                    # store "rsv1" flag
                    $msg->[2] = $header->{rsv1};
                }
            }

            # empty frame
            if ( !$header->{len} ) {
                $self->_on_frame( $header, \$msg, undef );
            }
            else {

                # check max. message size, return 1009 - message too big
                if ( $self->{max_message_size} ) {
                    if ( $msg && $msg->[0] ) {
                        return $self->disconnect( res [ 1009, $WEBSOCKET_STATUS_REASON ] ) if $header->{len} + length $msg->[0] > $self->{max_message_size};
                    }
                    else {
                        return $self->disconnect( res [ 1009, $WEBSOCKET_STATUS_REASON ] ) if $header->{len} > $self->{max_message_size};
                    }
                }

                my $payload = $h->read_chunk( $header->{len}, timeout => undef );

                # TODO status, proto error
                last if !$payload;

                $self->_on_frame( $header, \$msg, $payload );
            }
        }

        # TODO
        say '--- listen coro finished';

        return;
    };

    # auto-pong on timeout
    # if ( $self->{pong_timeout} ) {
    #     $self->{_h}->on_timeout( sub ($h) {
    #         return if !$self;

    #         $self->send_pong;

    #         return;
    #     } );

    #     $self->{_h}->timeout( $self->{pong_timeout} );
    # }

    $self->_on_connect;

    return;
}

# TODO $self is undef
sub _parse_frame_header ( $h ) {

    # read header
    my $buf_ref = $h->read_chunk( 2, timeout => undef );

    # header read error
    return if !$buf_ref;

    my ( $first, $second ) = unpack 'C*', substr $buf_ref->$*, 0, 2;

    my $masked = $second & 0b10000000;

    my $header = {
        len => $second & 0b01111111,

        # FIN
        fin => ( $first & 0b10000000 ) == 0b10000000 ? 1 : 0,

        # RSV1-3
        rsv1 => ( $first & 0b01000000 ) == 0b01000000 ? 1 : 0,
        rsv2 => ( $first & 0b00100000 ) == 0b00100000 ? 1 : 0,
        rsv3 => ( $first & 0b00010000 ) == 0b00010000 ? 1 : 0,

        # opcode
        op => $first & 0b00001111,
    };

    # small payload
    if ( $header->{len} < 126 ) {

        # read mask
        if ($masked) {
            my $mask = $h->read_chunk( 4, timeout => undef );

            # mask read error
            return if !$mask;

            $header->{mask} = $mask->$*;
        }
    }

    # extended payload (16-bit)
    elsif ( $header->{len} == 126 ) {
        my $buf = $h->read_chunk( $masked ? 6 : 2, timeout => undef );

        return if !$buf;

        $header->{len} = unpack 'n', substr $buf->$*, 0, 2;
        $header->{mask} = substr $buf->$*, 2, 4 if $masked;
    }

    # extended payload (64-bit with 32-bit fallback)
    elsif ( $header->{len} == 127 ) {
        my $buf = $h->read_chunk( $masked ? 12 : 8, timeout => undef );

        return if !$buf;

        $header->{len} = unpack 'Q>', substr $buf->$*, 0, 8;
        $header->{mask} = substr $buf->$*, 8, 4 if $masked;
    }

    return $header;
}

sub _on_frame ( $self, $header, $msg, $payload_ref ) {
    if ($payload_ref) {

        # unmask
        $payload_ref = \to_xor( $payload_ref->$*, $header->{mask} ) if $header->{mask};

        # decompress
        if ( $header->{rsv1} ) {
            my $inflate = $self->{_inflate} ||= Compress::Raw::Zlib::Inflate->new(
                -WindowBits => -15,
                ( $self->{max_message_size} ? ( -Bufsize => $self->{max_message_size} ) : () ),
                -AppendOutput => 0,
                -ConsumeInput => 1,
                -LimitOutput  => 1,
            );

            $payload_ref->$* .= "\x00\x00\xff\xff";

            $inflate->inflate( $payload_ref, my $out );

            return $self->disconnect( res [ 1009, $WEBSOCKET_STATUS_REASON ] ) if length $payload_ref->$*;

            $payload_ref = \$out;
        }
    }

    # this is message fragment frame
    if ( !$header->{fin} ) {

        # add frame to the message buffer
        $msg->$*->[0] .= $payload_ref->$* if $payload_ref;
    }

    # message completed, dispatch message
    else {
        $payload_ref = \( $msg->$*->[0] . $payload_ref->$* ) if $payload_ref && $msg->$* && defined $msg->$*->[0];

        # cleanup msg structure
        undef $msg->$*;

        # TEXT message
        if ( $header->{op} == $WEBSOCKET_OP_TEXT ) {
            $self->_on_text($payload_ref) if $payload_ref;
        }

        # BINARY message
        elsif ( $header->{op} == $WEBSOCKET_OP_BINARY ) {
            $self->_on_binary($payload_ref) if $payload_ref;
        }

        # CLOSE message
        elsif ( $header->{op} == $WEBSOCKET_OP_CLOSE ) {
            my ( $status, $reason );

            if ( $payload_ref && length $payload_ref->$* >= 2 ) {
                $status = unpack 'n', substr $payload_ref->$*, 0, 2, q[];

                $reason = decode_utf8 $payload_ref->$* if length $payload_ref->$*;
            }
            else {
                $status = 1006;    # 1006 - Abnormal Closure - if close status was not specified
            }

            $self->disconnect( res [ $status, $reason, $WEBSOCKET_STATUS_REASON ] );
        }

        # PING message
        elsif ( $header->{op} == $WEBSOCKET_OP_PING ) {

            # reply pong automatically
            $self->send_pong( $payload_ref ? $payload_ref->$* : q[] );

            $self->{on_ping}->( $self, $payload_ref || \q[] ) if $self->{on_ping};
        }

        # PONG message
        elsif ( $header->{op} == $WEBSOCKET_OP_PONG ) {
            $self->{on_pong}->( $self, $payload_ref || \q[] ) if $self->{on_pong};
        }
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 |                      | Subroutines::ProhibitExcessComplexity                                                                          |
## |      | 151                  | * Subroutine "connect" with high complexity score (29)                                                         |
## |      | 406                  | * Subroutine "__on_connect" with high complexity score (21)                                                    |
## |      | 584                  | * Subroutine "_on_frame" with high complexity score (29)                                                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 306, 312, 347        | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 528, 530, 532        | NamingConventions::ProhibitAmbiguousNames - Ambiguously named variable "second"                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 39, 600              | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::WebSocket::Handle

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
