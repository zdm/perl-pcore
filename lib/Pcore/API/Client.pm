package Pcore::API::Client;

use Pcore -class;
use Pcore::HTTP::WebSocket;
use Pcore::Util::Data qw[to_json from_json to_cbor from_cbor];
use Pcore::Util::UUID qw[uuid_str];
use Pcore::Util::Status::API::Keyword qw[status];

has uri => ( is => 'ro', isa => Str, required => 1 );    # http://token@host:port/api/, ws://token@host:port/api/
has token             => ( is => 'lazy', isa => Str );
has keepalive_timeout => ( is => 'ro',   isa => Maybe [PositiveOrZeroInt] );
has http_timeout      => ( is => 'ro',   isa => Maybe [PositiveOrZeroInt] );
has http_tls_ctx      => ( is => 'ro',   isa => Maybe [HashRef] );

has _uri => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::URI'], init_arg => undef );
has _is_http => ( is => 'lazy', isa => Bool, init_arg => undef );
has _ws => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::WebSocket'], init_arg => undef );
has _ws_connect_cache => ( is => 'ro', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _ws_cid_cache     => ( is => 'ro', isa => HashRef,  default => sub { {} }, init_arg => undef );

around BUILDARGS => sub ( $orig, $self, $uri, @ ) {
    my %args = ( splice @_, 3 );

    $args{uri} = $uri;

    return $self->$orig( \%args );
};

sub _build__uri($self) {
    return P->uri( $self->uri );
}

sub _build_token ($self) {
    return $self->_uri->userinfo;
}

sub _build__is_http ($self) {
    return $self->_uri->is_http;
}

# TODO make blocking call
sub api_call ( $self, $method, @ ) {
    my ( $cb, $args );

    # parse callback
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
            ( $self->http_timeout ? ( timeout => $self->http_timeout ) : () ),
            ( $self->http_tls_ctx ? ( tls_ctx => $self->http_tls_ctx ) : () ),
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

                # HTTP protocol or API call error
                if ( !$status ) {
                    $cb->( status [ $res->status, $res->reason ] ) if $cb;
                }
                else {
                    my $response = from_cbor $res->body;

                    $cb->( bless $response, 'Pcore::Util::Status::API' ) if $cb;
                }

                return;
            },
        );
    }

    # WebSocket protocol
    else {
        my $on_connect = sub ( $ws ) {
            my $cid;

            if ($cb) {
                $cid = uuid_str();

                $self->{_ws_cid_cache}->{$cid} = $cb;
            }

            $ws->send_binary(
                to_cbor(
                    {   cid    => $cid,
                        method => $method,
                        args   => $args,
                    }
                )->$*
            );

            return;
        };

        my $ws = $self->{_ws};

        if ( !$ws ) {
            my $on_error = sub ( $status, $reason ) {
                $cb->( status [ $status, $reason ] ) if $cb;

                return;
            };

            push $self->{_ws_connect_cache}->@*, [ $on_error, $on_connect ];

            return if $self->{_ws_connect_cache}->@* > 1;

            Pcore::HTTP::WebSocket->connect(
                $self->_uri,
                subprotocol     => 'pcore-api',
                headers         => [ 'Authorization' => 'token ' . $self->token, ],
                connect_timeout => 10,
                ( $self->http_timeout ? ( timeout => $self->http_timeout ) : () ),
                ( $self->http_tls_ctx ? ( tls_ctx => $self->http_tls_ctx ) : () ),
                on_proxy_connect_error => sub ( $status, $reason ) {
                    while ( my $callback = shift $self->{_ws_connect_cache}->@* ) {
                        $callback->[0]->( $status, $reason );
                    }

                    return;
                },
                on_connect_error => sub ( $status, $reason ) {
                    while ( my $callback = shift $self->{_ws_connect_cache}->@* ) {
                        $callback->[0]->( $status, $reason );
                    }

                    return;
                },
                on_connect => sub ( $ws, $headers ) {
                    $self->{_ws} = $ws;

                    while ( my $callback = shift $self->{_ws_connect_cache}->@* ) {
                        $callback->[1]->($ws);
                    }

                    return;
                },
                on_disconnect => sub ( $ws, $status, $reason ) {
                    undef $self->{_ws};

                    return;
                },
                on_binary => sub ( $ws, $payload_ref ) {

                    # decode CBOR payload
                    my $data = eval { from_cbor $payload_ref};

                    die q[WebSocket protocol error, can't decode CBOR payload] if $@;

                    # cid is present
                    if ( $data->{cid} ) {

                        # this is API call, not supported in API client yet, ignoring
                        if ( $data->{method} ) {
                            return;
                        }

                        # this is API callback
                        else {
                            if ( my $callback = delete $self->{_ws_cid_cache}->{ $data->{cid} } ) {
                                $callback->( bless $data, 'Pcore::Util::Status::API' ) if $callback;
                            }
                        }
                    }

                    # cid is not present
                    else {

                        # this is void API call, not supported in API client yet, ignoring
                        if ( $data->{method} ) {
                            return;
                        }

                        # this is error, cid and/or method must be specified
                        else {
                            return;
                        }
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
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 42                   | Subroutines::ProhibitExcessComplexity - Subroutine "api_call" with high complexity score (30)                  |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
