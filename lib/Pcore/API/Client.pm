package Pcore::API::Client;

use Pcore -class;
use Pcore::HTTP::WebSocket;
use Pcore::Util::Data qw[to_json from_json to_cbor from_cbor];
use Pcore::Util::Scalar qw[refaddr];
use Pcore::API::Response;

has uri => ( is => 'ro', isa => Str, required => 1 );    # http://token@host:port/api/, ws://token@host:port/api/
has token => ( is => 'lazy', isa => Str );
has keepalive_timeout => ( is => 'ro', isa => Maybe [PositiveOrZeroInt] );

has _uri => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::URI'], init_arg => undef );
has _is_http => ( is => 'lazy', isa => Bool, init_arg => undef );
has _ws => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::WebSocket'], init_arg => undef );
has _connect_cache => ( is => 'ro', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _request_cache => ( is => 'ro', isa => HashRef,  default => sub { {} }, init_arg => undef );

sub _build__uri($self) {
    return P->uri( $self->uri );
}

sub _build_token ($self) {
    return $self->_uri->userinfo;
}

sub _build__is_http ($self) {
    return $self->_uri->is_http;
}

sub api_call ( $self, $method, @ ) {
    my ( $cb, $args );

    if ( ref $_[-1] eq 'CODE' ) {
        $cb = $_[-1];

        $args = [ splice @_, 2, -1 ];
    }
    else {
        $args = [ splice @_, 2 ];
    }

    # HTTP protocol
    if ( $self->_is_http ) {
        P->http->get(
            $self->_uri,
            keepalive_timeout => $self->keepalive_timeout,
            headers           => {
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

    # WebSocket protocol
    else {
        my $on_connect = sub ( $ws ) {
            my $request_id;

            if ($cb) {
                $request_id = refaddr $cb;

                $self->{_request_cache}->{$request_id} = $cb;
            }

            $ws->send_binary(
                to_cbor(
                    {   request_id => $request_id,
                        method     => $method,
                        args       => $args,
                    }
                )->$*
            );

            return;
        };

        my $ws = $self->{_ws};

        if ( !$ws ) {
            my $on_error = sub ( $status, $reason ) {
                my $api_res = Pcore::API::Response->new( { status => $status, reason => $reason } );

                $cb->($api_res) if $cb;

                return;
            };

            push $self->{_connect_cache}->@*, [ $on_error, $on_connect ];

            return if $self->{_connect_cache}->@* > 1;

            Pcore::HTTP::WebSocket->connect(
                $self->_uri,
                subprotocol            => 'pcore-api',
                headers                => [ 'Authorization' => 'token ' . $self->token, ],
                connect_timeout        => 10,
                on_proxy_connect_error => sub ( $status, $reason ) {
                    while ( my $callback = shift $self->{_connect_cache}->@* ) {
                        $callback->[0]->( $status, $reason );
                    }

                    return;
                },
                on_connect_error => sub ( $status, $reason ) {
                    while ( my $callback = shift $self->{_connect_cache}->@* ) {
                        $callback->[0]->( $status, $reason );
                    }

                    return;
                },
                on_connect => sub ( $ws, $headers ) {
                    $self->{_ws} = $ws;

                    while ( my $callback = shift $self->{_connect_cache}->@* ) {
                        $callback->[1]->($ws);
                    }

                    return;
                },
                on_disconnect => sub ( $ws, $status, $reason ) {
                    undef $self->{_ws};

                    return;
                },
                on_binary => sub ( $ws, $payload_ref ) {

                    # decode payload
                    my $data = eval { from_cbor $payload_ref};

                    die q[WebSocket protocol error, can't decode CBOR payload] if $@;

                    if ( $data->{request_id} && ( my $callback = delete $self->{_request_cache}->{ $data->{request_id} } ) ) {
                        my $api_res = Pcore::API::Response->new( { status => $data->{status}, reason => $data->{reason} } );

                        $api_res->{result} = $data->{result} if $api_res->is_success;

                        $callback->($api_res);
                    }

                    return;
                },
            );
        }
        else {
            $on_connect->($ws);
        }
    }

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
