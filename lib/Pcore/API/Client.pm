package Pcore::API::Client;

use Pcore -class, -result;
use Pcore::HTTP::WebSocket;
use Pcore::Util::Data qw[to_json from_json to_cbor from_cbor];
use Pcore::Util::UUID qw[uuid_str];

has uri => ( is => 'ro', isa => Str, required => 1 );    # http://token@host:port/api/, ws://token@host:port/api/
has token => ( is => 'lazy', isa => Str );
has api_ver => ( is => 'ro', isa => Str, default => 'v1' );    # default API version for relative methods
has keepalive_timeout => ( is => 'ro', isa => Maybe [PositiveOrZeroInt] );
has http_timeout      => ( is => 'ro', isa => Maybe [PositiveOrZeroInt] );
has http_tls_ctx      => ( is => 'ro', isa => Maybe [HashRef] );

has _uri => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::URI'], init_arg => undef );
has _is_http => ( is => 'lazy', isa => Bool, init_arg => undef );
has _ws => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::WebSocket'], init_arg => undef );
has _ws_connect_cache => ( is => 'ro', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _ws_tid_cache     => ( is => 'ro', isa => HashRef,  default => sub { {} }, init_arg => undef );

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
    my ( $cb, $data );

    # parse callback
    if ( ref $_[-1] eq 'CODE' ) {
        $cb = $_[-1];

        $data = [ splice @_, 2, -1 ];
    }
    else {
        $data = [ splice @_, 2 ];
    }

    # add version to relative method id
    $method = "/$self->{api_ver}/$method" if substr( $method, 0, 1 ) ne q[/];

    # HTTP protocol
    if ( $self->_is_http ) {
        P->http->post(
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
                {   tid    => uuid_str(),
                    method => $method,
                    data   => $data,
                }
            ),
            on_finish => sub ($res) {

                if ($cb) {

                    # HTTP protocol error
                    if ( !$res ) {
                        $cb->( result [ $res->status, $res->reason ] );
                    }
                    else {
                        my $res_data = from_cbor $res->body;

                        if ( $res_data->[0]->{type} eq 'exception' ) {
                            $cb->( bless $res_data->[0]->{message}, 'Pcore::Util::Result' );
                        }
                        else {
                            $cb->( bless $res_data->[0]->{result}, 'Pcore::Util::Result' );
                        }
                    }
                }

                return;
            },
        );
    }

    # WebSocket protocol
    else {
        my $on_connect = sub ( $ws ) {
            my $tid;

            if ($cb) {
                $tid = uuid_str();

                $self->{_ws_tid_cache}->{$tid} = $cb;
            }

            $ws->send_binary(
                to_cbor(
                    {   tid    => $tid,
                        method => $method,
                        data   => $data,
                    }
                )->$*
            );

            return;
        };

        my $ws = $self->{_ws};

        if ( !$ws ) {
            my $on_error = sub ( $status, $reason ) {
                $cb->( result [ $status, $reason ] ) if $cb;

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
                    my $res_data = eval { from_cbor $payload_ref};

                    die q[WebSocket protocol error, can't decode CBOR payload] if $@;

                    # tid is present
                    if ( $res_data->{tid} ) {

                        # this is API call, not supported in API client yet, ignoring
                        if ( $res_data->{method} ) {
                            return;
                        }

                        # this is API callback
                        else {
                            if ( my $callback = delete $self->{_ws_tid_cache}->{ $res_data->{tid} } ) {
                                if ( $res_data->[0]->{type} eq 'exception' ) {
                                    $callback->( bless $res_data->[0]->{message}, 'Pcore::Util::Result' );
                                }
                                else {
                                    $callback->( bless $res_data->[0]->{result}, 'Pcore::Util::Result' );
                                }
                            }
                        }
                    }

                    # tid is not present
                    else {

                        # this is void API call, not supported in API client yet, ignoring
                        if ( $res_data->{method} ) {
                            return;
                        }

                        # this is error, tid and/or method must be specified
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
## |    3 | 42                   | Subroutines::ProhibitExcessComplexity - Subroutine "api_call" with high complexity score (33)                  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 190                  | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
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
