package Pcore::API::Client;

use Pcore -class;
use Pcore::HTTP::WebSocket;
use Pcore::Util::Data qw[to_json from_json to_cbor from_cbor];
use Pcore::Util::Scalar qw[refaddr];
use Pcore::API::Response;

has uri => ( is => 'ro', isa => Str, required => 1 );    # http://token@host:port/api/, ws://token@host:port/api/
has token => ( is => 'lazy', isa => Str );

has _uri => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::URI'], init_arg => undef );
has _is_http => ( is => 'lazy', isa => Bool, init_arg => undef );
has _ws => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::WebSocket'], init_arg => undef );
has _request_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

sub _build__uri($self) {
    return P->uri( $self->uri );
}

sub _build_token ($self) {
    return $self->_uri->userinfo;
}

sub _build__is_http ($self) {
    return $self->_uri->is_http;
}

# TODO connect websocket on demand, wrap connection errors

sub api_call ( $self, $method, @ ) {
    my ( $cb, $args );

    if ( ref $_[-1] eq 'CODE' ) {
        $cb = $_[-1];

        $args = [ splice @_, 2, -1 ];
    }
    else {
        $args = [ splice @_, 2 ];
    }

    if ( $self->_is_http ) {
        P->http->get(
            $self->_uri,
            headers => {
                REFERER       => undef,
                AUTHORIZATION => 'token ' . $self->token,
                CONTENT_TYPE  => 'application/cbor',
            },
            body => to_cbor(
                {   method => $method,
                    args   => $args,
                }
            ),
            on_finish => sub ($res) {
                my $api_res = Pcore::API::Response->new( { status => $res->status, reason => $res->reason } );

                if ( $res->is_success ) {
                    my $response = from_cbor $res->body;

                    $api_res->{result} = $response->{result};
                }

                $cb->($api_res) if $cb;

                return;
            },
        );
    }
    else {
        $self->_websocket_connect(
            sub ($usccess) {
                my $request_id;

                if ($cb) {
                    $request_id = refaddr $cb;

                    $self->{_request_cache}->{$request_id} = $cb;
                }

                $self->{_ws}->send_binary(
                    to_cbor(
                        {   request_id => $request_id,
                            method     => $method,
                            args       => $args,
                        }
                    )->$*
                );

                return;
            }
        );
    }

    return;
}

sub _websocket_connect ( $self, $cb ) {
    Pcore::HTTP::WebSocket->connect(
        $self->_uri,
        subprotocol      => 'pcore-api',
        headers          => [ 'Authorization' => 'token ' . $self->token, ],
        on_connect_error => sub ($ws) {
            die q[websocket connect error];
        },
        on_connect => sub ( $ws, $headers ) {
            $self->{_ws} = $ws;

            say 'CONNECTED';

            $cb->(1);

            return;
        },
        on_text => sub ( $ws, $payload_ref ) {
            die q[Text messages are not used];
        },
        on_binary => sub ( $ws, $payload_ref ) {

            # decode payload
            my $data = eval { from_cbor $payload_ref};

            if ( $data->{request_id} ) {
                my $cb = delete $self->{_request_cache}->{ $data->{request_id} };

                $cb->($data) if $cb;
            }

            return;
        },
        on_pong => sub ( $ws, $payload ) {
            return;
        },
        on_disconnect => sub ( $ws, $status, $reason ) {
            say "DISCONNECTED: $status, $reason";

            undef $self->{_ws};

            return;
        },
    );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Client

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
