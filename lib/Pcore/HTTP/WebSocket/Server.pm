package Pcore::HTTP::WebSocket::Server;

use Pcore -role;
use Pcore::HTTP::WebSocket::Connection;

requires qw[run ws_protocol ws_permessage_deflate ws_max_message_size ws_autopong ws_on_accept ws_on_connect ws_on_disconnect ws_on_text ws_on_binary ws_on_pong];

around run => sub ( $orig, $self, $req ) {

    # this is websocket connect request
    if ( $req->is_websocket_connect_request ) {
        my $env = $req->{env};

        # websocket version is not specified or not supported
        return $req->return_xxx( [ 400, q[Unsupported WebSocket version] ] ) if !$env->{HTTP_SEC_WEBSOCKET_VERSION} || $env->{HTTP_SEC_WEBSOCKET_VERSION} ne $Pcore::HTTP::WebSocket::Connection::WEBSOCKET_VERSION;

        # websocket key is not specified
        return $req->return_xxx( [ 400, q[WebSocket SEC_WEBSOCKET_KEY header is required] ] ) if !$env->{HTTP_SEC_WEBSOCKET_KEY};

        # check websocket protocol
        my $ws_protocol = $self->ws_protocol;

        if ( $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} ) {
            return $req->return_xxx( [ 400, q[Unsupported WebSocket protocol requested] ] ) if !$ws_protocol || $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} !~ /\b$ws_protocol\b/smi;
        }
        elsif ($ws_protocol) {
            return $req->return_xxx( [ 400, q[WebSocket client requested no protocol] ] );
        }

        # create empty websocket object
        my $ws = bless {}, 'Pcore::HTTP::WebSocket::Connection';

        my $accept = sub ($headers = undef) {
            my $ws_permessage_deflate = 0;

            # check and set extensions
            if ( $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} ) {

                # set ext_permessage_deflate, only if enabled locally
                $ws_permessage_deflate = 1 if $self->ws_permessage_deflate && $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} =~ /\bpermessage-deflate\b/smi;
            }

            # create response headers
            my @headers = (    #
                'Sec-WebSocket-Accept' => Pcore::HTTP::WebSocket::Connection->challenge( $env->{HTTP_SEC_WEBSOCKET_KEY} ),
                ( $ws_protocol           ? ( 'Sec-WebSocket-Protocol'   => $ws_protocol )         : () ),
                ( $ws_permessage_deflate ? ( 'Sec-WebSocket-Extensions' => 'permessage-deflate' ) : () ),
            );

            # add custom headers
            push @headers, $headers->@* if $headers;

            # accept websocket connection
            $ws->{h} = $req->accept_websocket( \@headers );

            # initialize websocket object
            $ws->{max_message_size}   = $self->ws_max_message_size;
            $ws->{permessage_deflate} = $ws_permessage_deflate;

            # initialize callbacks
            $ws->{on_disconnect} = sub ( $ws, $status, $reason ) {
                $self->ws_on_disconnect( $ws, $status, $reason );

                return;
            };

            $ws->{on_text} = sub ( $ws, $data_ref ) {
                $self->ws_on_text( $ws, $data_ref );

                return;
            };

            $ws->{on_binary} = sub ( $ws, $data_ref ) {
                $self->ws_on_binary( $ws, $data_ref );

                return;
            };

            $ws->{on_pong} = sub ( $ws, $data_ref ) {
                $self->ws_on_pong( $ws, $data_ref );

                return;
            };

            # start autopong
            $ws->start_autopong( $self->ws_autopong ) if $self->ws_autopong;

            $ws->start_listen;

            $self->ws_on_connect($ws);

            return;
        };

        my $decline = sub ( $status = 400, $headers = undef ) {
            $req->( $status, $headers )->finish;

            return;
        };

        $self->ws_on_accept( $ws, $req, $accept, $decline );

        return;
    }

    # this is NOT websocket connect request
    else {
        return $self->$orig($req);
    }
};

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::WebSocket::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
