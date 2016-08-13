package Pcore::App::Controller::WebSocket;

use Pcore -role;
use Pcore::HTTP::WebSocket;
use Pcore::Util::Scalar qw[refaddr];

with qw[Pcore::App::Controller];

has websocket_subprotocol => ( is => 'ro', isa => Maybe [Str], builder => '_build_websocket_subprotocol' );
has websocket_max_message_size => ( is => 'ro', isa => PositiveOrZeroInt, builder => '_build_websocket_max_message_size' );    # 0 - do not check
has websocket_permessage_deflate => ( is => 'ro', isa => Bool, builder => '_build_websocket_permessage_deflate' );

# send pong automatically on handle timeout
# this parameter should be less, than nginx "proxy_read_timeout" in nginx
has websocket_autopong => ( is => 'ro', isa => PositiveOrZeroInt, builder => '_build_websocket_autopong' );    # 0 - do not ping on timeout

has _websocket_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

sub _build_websocket_subprotocol ($self) {
    return;
}

sub _build_websocket_max_message_size ($self) {
    return 1024 * 1024 * 10;
}

sub _build_websocket_permessage_deflate ($self) {
    return 1;
}

sub _build_websocket_autopong ($self) {
    return 50;
}

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

        # create empty websocket object
        my $ws = bless {}, 'Pcore::HTTP::WebSocket';

        my $accept = sub ($headers = undef) {
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
            push @headers, $headers->@* if $headers;

            # accept websocket connection
            $ws->{h} = $req->accept_websocket( \@headers );

            # initialize websocket object
            $ws->{max_message_size}   = $self->{websocket_max_message_size};
            $ws->{permessage_deflate} = $permessage_deflate;

            # initialize callbacks
            $ws->{on_text} = sub ( $ws, $payload_ref ) {
                $self->websocket_on_text( $ws, $payload_ref );

                return;
            };
            $ws->{on_binary} = sub ( $ws, $payload_ref ) {
                $self->websocket_on_binary( $ws, $payload_ref );

                return;
            };
            $ws->{on_pong} = sub ( $ws, $payload_ref ) {
                $self->websocket_on_pong( $ws, $payload_ref );

                return;
            };
            $ws->{on_disconnect} = sub ( $ws, $status, $reason ) {
                $self->websocket_on_disconnect( $ws, $status, $reason );

                return;
            };

            # store websocket object in cache, using refaddr as key
            $self->{_websocket_cache}->{ refaddr $ws} = $ws;

            # start autopong
            $ws->start_autopong( $self->{websocket_autopong} ) if $self->{websocket_autopong};

            $ws->start_listen;

            $self->websocket_on_connect($ws);

            return;
        };

        my $decline = sub ( $status = 400, $headers = undef ) {
            $req->write( $status, $headers )->finish;

            return;
        };

        $self->websocket_on_accept( $ws, $req, $accept, $decline );

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

# called, before websocket connection accept
# should return $accept, \@headers = undef
# needed connection variables can  de stored in the $ws object attributes for further usage
sub websocket_on_accept ( $self, $ws, $req, $accept, $decline ) {
    $accept->();

    return;
}

# called, when websocket connection is accepted and ready for use
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
