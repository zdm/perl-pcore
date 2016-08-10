package Pcore::App::Controller::WebSocket;

use Pcore -role;
use Pcore::HTTP::WebSocket;
use Pcore::Util::Scalar qw[refaddr];

with qw[Pcore::App::Controller];

has websocket_subprotocol => ( is => 'ro', isa => Maybe [Str] );
has websocket_max_message_size => ( is => 'ro', isa => PositiveOrZeroInt, default => 1024 * 1024 * 10 );    # 10 Mb, 0 - do not check
has websocket_permessage_deflate => ( is => 'ro', isa => Bool, default => 1 );

# send pong automatically on handle timeout
# this parameter should be less, than nginx "proxy_read_timeout" in nginx
has websocket_autopong => ( is => 'ro', isa => PositiveOrZeroInt, default => 50 );    # 0 - do not ping on timeout

has _websocket_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

around run => sub ( $orig, $self, $req ) {

    # this is websocket connect request
    if ( $req->is_websocket_connect_request ) {
        my $env = $req->{env};

        # websocket version is not specified or not supported
        return $req->return_xxx( [ 400, q[Unsupported WebSocket version] ] ) if !$env->{HTTP_SEC_WEBSOCKET_VERSION} || $env->{HTTP_SEC_WEBSOCKET_VERSION} ne $Pcore::HTTP::WebSocket::WEBSOCKET_VERSION;

        # websocket key is not specified
        return $req->return_xxx( [ 400, q[WebSocket SEC_WEBSOCKET_KEY header is required] ] ) if !$env->{HTTP_SEC_WEBSOCKET_KEY};

        # check websocket subprotocol
        my $websocket_subprotocol = $self->websocket_subprotocol;

        if ( $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} ) {
            return $req->return_xxx( [ 400, q[Unsupported WebSocket subprotocol requested] ] ) if !$websocket_subprotocol || $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} !~ /\b$websocket_subprotocol\b/smi;
        }
        elsif ($websocket_subprotocol) {
            return $req->return_xxx( [ 400, q[WebSocket client requested no subprotocol] ] );
        }

        my ( $websocket_accept, $accept_headers ) = $self->websocket_on_accept($req);

        # websocket connect request can't be accepted
        return $req->return_xxx( $accept_headers // 400 ) if !$websocket_accept;

        my $permessage_deflate = 0;

        # check and set extensions
        if ( $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} ) {

            # set ext_permessage_deflate, only if enabled locally
            $permessage_deflate = 1 if $self->{websocket_permessage_deflate} && $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} =~ /\bpermessage-deflate\b/smi;
        }

        # create response headers
        my @headers = (    #
            'Sec-WebSocket-Accept' => Pcore::HTTP::WebSocket->challenge( $env->{HTTP_SEC_WEBSOCKET_KEY} ),
            ( $websocket_subprotocol ? ( 'Sec-WebSocket-Protocol'   => $websocket_subprotocol ) : () ),
            ( $permessage_deflate    ? ( 'Sec-WebSocket-Extensions' => 'permessage-deflate' )   : () ),
        );

        # add custom headers
        push @headers, $accept_headers->@* if $accept_headers;

        # accept websocket connection
        my $ws = Pcore::HTTP::WebSocket->new(
            {   h                  => $req->accept_websocket( \@headers ),
                max_message_size   => $self->{websocket_max_message_size},
                permessage_deflate => $permessage_deflate,
                on_text            => sub ( $ws, $payload_ref ) {
                    $self->websocket_on_text( $ws, $payload_ref );

                    return;
                },
                on_binary => sub ( $ws, $payload_ref ) {
                    $self->websocket_on_binary( $ws, $payload_ref );

                    return;
                },
                on_pong => sub ( $ws, $payload_ref ) {
                    $self->websocket_on_pong( $ws, $payload_ref );

                    return;
                },
                on_disconnect => sub ( $ws, $status, $reason ) {
                    $self->websocket_on_disconnect( $ws, $status, $reason );

                    return;
                },
            }
        );

        # store websocket object in HTTP server cache, using refaddr as key
        $self->{_websocket_cache}->{ refaddr $ws} = $ws;

        # start autopong
        $ws->start_autopong( $self->{websocket_autopong} ) if $self->{websocket_autopong};

        $ws->start_listen;

        return;
    }

    # this is NOT websocket connect request
    else {
        return $self->$orig($req);
    }
};

around websocket_disconnect => sub ( $orig, $self, $ws, $status, $reason = undef ) {

    # remove websocket connection from cache
    delete $self->{_websocket_cache}->{ refaddr $ws};

    $ws->disconnect( $status, $reason );

    return $self->$orig( $ws, $status, $ws->{reason} );
};

around websocket_on_disconnect => sub ( $orig, $self, $ws, $status, $reason ) {

    # remove websocket connection from cache
    delete $self->{_websocket_cache}->{ refaddr $ws};

    return $self->$orig( $ws, $status, $reason );
};

# LOOPBACK METHODS, CAN BE REDEFINED
# called, before websocket connection accept
# NOTE websocket_on_accept - perform additional checks, return true or headers array on success, or false, if connection is not possible
sub websocket_on_accept ( $self, $ws, $req ) {
    return 1;
}

# called, when websocket connection is accepted and ready to use
sub websocket_on_connect ( $self, $ws ) {
    return;
}

sub websocket_on_text ( $self, $ws, $payload_ref ) {
    return;
}

sub websocket_on_binary ( $self, $ws, $payload_ref ) {
    return;
}

sub websocket_on_pong ( $self, $ws, $payload ) {
    return;
}

# should be called, when local peer decided to close connection
sub websocket_disconnect ( $self, $ws, $status, $reason = undef ) {
    return;
}

# called, when remote peer close connection or on protocol errors
sub websocket_on_disconnect ( $self, $ws, $status, $reason ) {
    return;
}

1;
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
