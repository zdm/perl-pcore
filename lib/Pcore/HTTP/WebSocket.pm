package Pcore::HTTP::WebSocket;

use Pcore -const, -class;
use Pcore::Util::Text qw[decode_utf8 encode_utf8];
use Pcore::Util::Data qw[to_b64 to_xor];
use Pcore::Util::List qw[pairs];
use Pcore::Util::Random qw[random_bytes];
use Pcore::AE::Handle;
use Compress::Raw::Zlib;
use Digest::SHA1 qw[];

# https://tools.ietf.org/html/rfc6455

has h => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'], required => 1 );
has max_message_size => ( is => 'ro', isa => PositiveOrZeroInt, required => 1 );    # 0 - do not check

# http://www.iana.org/assignments/websocket/websocket.xml#extension-name
# https://tools.ietf.org/html/rfc7692#page-10
# https://www.igvita.com/2013/11/27/configuring-and-optimizing-websocket-compression/
has permessage_deflate => ( is => 'ro', isa => Bool, required => 1 );

# callbacks
has on_text       => ( is => 'ro', isa => Maybe [CodeRef] );
has on_binary     => ( is => 'ro', isa => Maybe [CodeRef] );
has on_pong       => ( is => 'ro', isa => Maybe [CodeRef] );
has on_disconnect => ( is => 'ro', isa => Maybe [CodeRef] );

has status => ( is => 'ro', isa => Bool, init_arg => undef );    # close status, undef - opened
has reason => ( is => 'ro', isa => Str,  init_arg => undef );    # close reason, undef - opened

# mask data on send, for websocket client only
has _send_masked => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

has _msg => ( is => 'ro', isa => ArrayRef, init_arg => undef );    # fragmentated message data, [$payload, $op, $rsv1]
has _deflate => ( is => 'ro', init_arg => undef );
has _inflate => ( is => 'ro', init_arg => undef );

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

sub connect ( $self, $uri, @ ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    $uri = Pcore->uri($uri) if !ref $uri;

    my %args = (

        # websocket args
        subprotocol        => undef,
        max_message_size   => 1024 * 1024 * 10,               # 10 Mb
        permessage_deflate => 1,
        useragent          => "Pcore-HTTP/$Pcore::VERSION",
        headers            => undef,                          # ArrayRef

        # create handle args
        handle_params          => {},
        connect_timeout        => undef,
        tls_ctx                => undef,
        bind_ip                => undef,
        proxy                  => undef,
        on_proxy_connect_error => undef,
        on_connect_error       => undef,
        on_connect             => undef,
        splice @_, 2,
    );

    Pcore::AE::Handle->new(
        persistent => 0,
        $args{handle_params}->%*,
        connect         => $uri,
        connect_timeout => $args{connect_timeout},
        tls_ctx         => $args{tls_ctx},
        bind_ip         => $args{bind_ip},
        proxy           => $args{proxy},
        on_proxy_connect_error => sub ( $h, $reason, $proxy_error ) {
            if ( $args{on_proxy_connect_error} ) {
                $args{on_proxy_connect_error}->( 594, $reason, $proxy_error );
            }
            elsif ( $args{on_connect_error} ) {
                $args{on_proxy_connect_error}->( 594, $reason );
            }
            else {
                die qq[WebSocket proxy connect error: 594, $reason, $proxy_error];
            }

            return;
        },
        on_connect_error => sub ( $h, $reason ) {
            if ( $args{on_connect_error} ) {
                $args{on_connect_error}->( 595, $reason );
            }
            else {
                die qq[WebSocket connect error: 595, $reason];
            }

            return;
        },
        on_error => sub ( $h, $fatal, $reason ) {
            if ( $args{on_connect_error} ) {
                $args{on_connect_error}->( 596, $reason );
            }
            else {
                die qq[WebSocket connect error: 596, $reason];
            }

            return;
        },
        on_connect => sub ( $h, $host, $port, $retry ) {

            # start TLS, only if TLS is required and TLS is not established yet
            $h->starttls('connect') if $uri->is_secure && !exists $h->{tls};

            # generate websocket key
            my $sec_websocket_key = to_b64 rand 100_000, q[];

            my $request_path = $uri->path->to_uri . ( $uri->query ? q[?] . $uri->query : q[] );

            my @headers = (    #
                "GET $request_path HTTP/1.1",
                'Host:' . $uri->host,
                'Upgrade:websocket',
                'Connection:upgrade',
                "Sec-WebSocket-Version:$WEBSOCKET_VERSION",
                "Sec-WebSocket-Key:$sec_websocket_key",
                ( $args{subprotocol}        ? "Sec-WebSocket-Protocol:$args{subprotocol}"   : () ),
                ( $args{permessage_deflate} ? 'Sec-WebSocket-Extensions:permessage-deflate' : () ),
                ( $args{useragent}          ? "User-Agent:$args{useragent}"                 : () ),
            );

            push @headers, map {"$_->[0]:$_->[1]"} pairs $args{headers}->@* if $args{headers};

            $h->push_write( join( $CRLF, @headers ) . $CRLF . $CRLF );

            $h->read_http_res_headers(
                headers => 1,
                sub ( $h1, $headers, $error_reason ) {
                    my $error_status;

                    my $res_headers;

                    if ($error_reason) {

                        # headers parsing error
                        $error_status = 596;
                    }
                    else {
                        $res_headers = $headers->{headers};

                        # check response status
                        if ( $headers->{status} != 101 ) {
                            $error_status = $headers->{status};
                            $error_reason = $headers->{reason};
                        }

                        # check response connection headers
                        elsif ( !$res_headers->{CONNECTION} || !$res_headers->{UPGRADE} || $res_headers->{CONNECTION} !~ /\bupgrade\b/smi || $res_headers->{UPGRADE} !~ /\bwebsocket\b/smi ) {
                            $error_status = 596;
                            $error_reason = q[WebSocket handshake error];
                        }

                        # check SEC_WEBSOCKET_ACCEPT
                        elsif ( !$res_headers->{SEC_WEBSOCKET_ACCEPT} || $res_headers->{SEC_WEBSOCKET_ACCEPT} ne $self->challenge($sec_websocket_key) ) {
                            $error_status = 596;
                            $error_reason = q[Invalid WebSocket SEC_WEBSOCKET_ACCEPT];
                        }

                        # check subprotocol
                        else {
                            if ( $res_headers->{SEC_WEBSOCKET_PROTOCOL} ) {
                                if ( !$args{subprotocol} || $res_headers->{SEC_WEBSOCKET_PROTOCOL} !~ /\b$args{subprotocol}\b/smi ) {
                                    $error_status = 596;
                                    $error_reason = qq[WebSocket server returned unsupported supbrotocol "$res_headers->{SEC_WEBSOCKET_PROTOCOL}"];
                                }
                            }
                            elsif ( $args{subprotocol} ) {
                                $error_status = 596;
                                $error_reason = q[WebSocket server returned no supbrotocol];
                            }
                        }
                    }

                    if ($error_status) {
                        if ( $args{on_connect_error} ) {
                            $args{on_connect_error}->( $error_status, $error_reason );
                        }
                        else {
                            die qq[WebSocket connect error: $error_status, $error_reason];
                        }
                    }
                    else {
                        my $permessage_deflate = 0;

                        # check and set extensions
                        if ( $res_headers->{SEC_WEBSOCKET_EXTENSIONS} ) {
                            $permessage_deflate = 1 if $args{permessage_deflate} && $res_headers->{SEC_WEBSOCKET_EXTENSIONS} =~ /\bpermessage-deflate\b/smi;
                        }

                        $args{h}                  = $h;
                        $args{permessage_deflate} = $permessage_deflate;

                        my $ws = $self->new( \%args );

                        # client always send masked frames
                        $ws->{_send_masked} = 1;

                        $ws->start_listen;

                        $args{on_connect}->( $ws, $res_headers ) if $args{on_connect};
                    }

                    return;
                }
            );

            return;
        },
    );

    return;
}

sub send_text ( $self, $payload ) {
    $self->{h}->push_write( $self->_build_frame( 1, $self->{permessage_deflate}, 0, 0, $WEBSOCKET_OP_TEXT, \encode_utf8 $payload) );

    return;
}

sub send_binary ( $self, $payload ) {
    $self->{h}->push_write( $self->_build_frame( 1, $self->{permessage_deflate}, 0, 0, $WEBSOCKET_OP_BINARY, \$payload ) );

    return;
}

sub ping ( $self, $payload = $WEBSOCKET_PING_PONG_PAYLOAD ) {
    $self->{h}->push_write( $self->_build_frame( 1, 0, 0, 0, $WEBSOCKET_OP_PING, \$payload ) );

    return;
}

sub pong ( $self, $payload = $WEBSOCKET_PING_PONG_PAYLOAD ) {
    $self->{h}->push_write( $self->_build_frame( 1, 0, 0, 0, $WEBSOCKET_OP_PONG, \$payload ) );

    return;
}

sub disconnect ( $self, $status, $reason = undef ) {

    # connection already closed
    return if defined $self->{status};

    # mark connection as closed
    $self->{status} = $status;

    $self->{reason} = $reason //= $WEBSOCKET_CLOSE_REASON->{$status} // 'Unknown reason';

    # cleanup fragmentated message data
    undef $self->{_msg};

    # send close message
    $self->{h}->push_write( $self->_build_frame( 1, 0, 0, 0, $WEBSOCKET_OP_CLOSE, \( pack( 'n', $status ) . encode_utf8 $reason ) ) );

    # destroy handle
    $self->{h}->destroy;

    return;
}

# UTILS
sub challenge ( $self, $key ) {
    return to_b64( Digest::SHA1::sha1( ($key) . $WEBSOCKET_GUID ), q[] );
}

sub start_listen ($self) {

    # cleanup fragmentated message data
    undef $self->{_msg};

    $self->{h}->on_error(
        sub ( $h, @ ) {
            $self->_on_close(1001) if !defined $self->{status};    # 1001 - Going Away

            return;
        }
    );

    $self->{h}->on_read(
        sub ($h) {
            if ( my $header = $self->_parse_frame_header( \$h->{rbuf} ) ) {

                # check protocol errors
                if ( $header->{fin} ) {

                    # this is the last frame of the fragmentated message
                    if ( $header->{op} == $WEBSOCKET_OP_CONTINUATION ) {

                        # message was not started, return 1002 - protocol error
                        return $self->_on_close(1002) if !$self->{_msg};

                        # restore message "op", "rsv1"
                        ( $header->{op}, $header->{rsv1} ) = ( $self->{_msg}->[1], $self->{_msg}->[2] );
                    }

                    # this is the single-frame message
                    else {

                        # set "rsv1" flag
                        $header->{rsv1} = $self->{permessage_deflate} && $header->{rsv1} ? 1 : 0;
                    }
                }
                else {

                    # this is the next frame of the fragmentated message
                    if ( $header->{op} == $WEBSOCKET_OP_CONTINUATION ) {

                        # message was not started, return 1002 - protocol error
                        return $self->_on_close(1002) if !$self->{_msg};

                        # restore "rsv1" flag
                        $header->{rsv1} = $self->{_msg}->[2];
                    }

                    # this is the first frame of the fragmentated message
                    else {

                        # store message "op"
                        $self->{_msg}->[1] = $header->{op};

                        # set and store "rsv1" flag
                        $self->{_msg}->[2] = $header->{rsv1} = $self->{permessage_deflate} && $header->{rsv1} ? 1 : 0;
                    }
                }

                # empty frame
                if ( !$header->{len} ) {
                    $self->_on_frame( $header, undef );
                }
                else {

                    # check max. message size, return 1009 - message too big
                    if ( $self->{max_message_size} ) {
                        if ( $self->{_msg} && $self->{_msg}->[0] ) {
                            return $self->_on_close(1009) if $header->{len} + length $self->{_msg}->[0] > $self->{max_message_size};
                        }
                        else {
                            return $self->_on_close(1009) if $header->{len} > $self->{max_message_size};
                        }
                    }

                    if ( length $h->{rbuf} >= $header->{len} ) {
                        $self->_on_frame( $header, \substr $h->{rbuf}, 0, $header->{len}, q[] );
                    }
                    else {
                        $h->unshift_read(
                            chunk => $header->{len},
                            sub ( $h, $payload ) {
                                $self->_on_frame( $header, \$payload );

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

sub start_autopong ( $self, $timeout ) {
    $self->{h}->on_timeout(
        sub ($h) {
            $self->pong;

            return;
        }
    );

    $self->{h}->timeout($timeout);

    return;
}

sub _on_frame ( $self, $header, $payload_ref ) {
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

            return $self->_on_close(1009) if length $payload_ref->$*;

            $payload_ref = \$out;
        }
    }

    # this is message fragment frame
    if ( !$header->{fin} ) {

        # add frame to the message buffer
        $self->{_msg}->[0] .= $payload_ref->$* if $payload_ref;
    }

    # message completed, dispatch message
    else {
        if ( $self->{_msg} ) {
            $payload_ref = \( $self->{_msg}->[0] . $payload_ref->$* ) if $payload_ref && defined $self->{_msg}->[0];

            # cleanup fragmentated message data
            undef $self->{_msg};
        }

        # dispatch message
        # TEXT message
        if ( $header->{op} == $WEBSOCKET_OP_TEXT ) {
            if ($payload_ref) {
                eval { decode_utf8 $payload_ref->$* };

                return $self->_on_close( 1003, 'UTF-8 decode error' ) if $@;

                $self->{on_text}->( $self, $payload_ref ) if $self->{on_text};
            }
        }

        # BINARY message
        elsif ( $header->{op} == $WEBSOCKET_OP_BINARY ) {
            $self->{on_binary}->( $self, $payload_ref ) if $payload_ref && $self->{on_binary};
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

            $self->_on_close( $status, $reason );
        }

        # PING message
        elsif ( $header->{op} == $WEBSOCKET_OP_PING ) {

            # send pong automatically
            $self->pong( $payload_ref ? $payload_ref->$* : q[] );
        }

        # PONG message
        elsif ( $header->{op} == $WEBSOCKET_OP_PONG ) {
            $self->{on_pong}->( $self, $payload_ref ? $payload_ref->$* : q[] ) if $self->{on_pong};
        }
    }

    return;
}

# called automatically, when remote peer close connection
sub _on_close ( $self, $status, $reason = undef ) {

    # connection already closed
    return if defined $self->{status};

    $reason //= $WEBSOCKET_CLOSE_REASON->{$status} // 'Unknown reason';

    # close connection
    $self->disconnect( $status, $reason );

    # call on_disconnect callback
    $self->{on_disconnect}->( $self, $status, $reason ) if $self->{on_disconnect};

    return;
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
        my $mask = pack 'N', int( rand 9 x 7 );

        $payload_ref = \( $mask . to_xor( $payload_ref->$*, $mask ) );
    }

    return $frame . $payload_ref->$*;
}

sub _parse_frame_header ( $self, $buf_ref ) {
    return if length $buf_ref->$* < 2;

    my ( $first, $second ) = unpack 'C*', substr $buf_ref->$*, 0, 2;

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
## |      | 70                   | * Subroutine "connect" with high complexity score (38)                                                         |
## |      | 300                  | * Subroutine "start_listen" with high complexity score (25)                                                    |
## |      | 413                  | * Subroutine "_on_frame" with high complexity score (30)                                                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 96                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 261, 267, 521        | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 459                  | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 582, 584             | NamingConventions::ProhibitAmbiguousNames - Ambiguously named variable "second"                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 41, 429              | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::WebSocket

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
