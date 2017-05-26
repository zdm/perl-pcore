package Pcore::API::Client;

use Pcore -class, -result;
use Pcore::WebSocket;
use Pcore::Util::Scalar qw[blessed weaken];
use Pcore::Util::Data qw[to_cbor from_cbor];
use Pcore::Util::UUID qw[uuid_str];
use Pcore::HTTP qw[:TLS_CTX];

has uri => ( is => 'ro', isa => InstanceOf ['Pcore::Util::URI'], required => 1 );    # http://token@host:port/api/, ws://token@host:port/api/

has token   => ( is => 'ro', isa => Str );
has api_ver => ( is => 'ro', isa => Str );                                           # eg: 'v1', default API version for relative methods

has tls_ctx => ( is => 'ro', isa => Maybe [ HashRef | Enum [ $TLS_CTX_LOW, $TLS_CTX_HIGH ] ], default => $TLS_CTX_HIGH );
has connect_timeout => ( is => 'ro', isa => PositiveOrZeroInt, default => 10 );

# HTTP options
has persistent => ( is => 'ro', isa => Maybe [PositiveOrZeroInt], default => 600 );
has timeout => ( is => 'ro', isa => Maybe [PositiveOrZeroInt] );

# WebSocket options
has compression => ( is => 'ro', isa => Bool, default => 0 );
has on_disconnect => ( is => 'ro', isa => Maybe [CodeRef] );
has on_rpc        => ( is => 'ro', isa => Maybe [CodeRef] );

has _is_http => ( is => 'lazy', isa => Bool, required => 1 );

has _get_ws_cb => ( is => 'ro', isa => ArrayRef, init_arg => undef );
has _ws => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::WebSocket'], init_arg => undef );

sub DEMOLISH ( $self, $global ) {
    if ( !$global ) {
        $self->{_ws}->disconnect if $self->{_ws};
    }

    return;
}

around BUILDARGS => sub ( $orig, $self, $uri, @ ) {
    my %args = ( splice @_, 3 );

    $args{uri} = P->uri($uri);

    $args{token} = $args{uri}->userinfo if !$args{token};

    $args{_is_http} = $args{uri}->is_http;

    return $self->$orig( \%args );
};

sub set_token ( $self, $token = undef ) {
    if ( $token // q[] ne $self->{token} // q[] ) {
        $self->{token} = $token;

        $self->disconnect;
    }

    return;
}

sub disconnect ($self) {
    undef $self->{_ws};

    return;
}

# TODO make blocking call
sub api_call ( $self, $method, @args ) {

    # add version to relative method id
    if ( substr( $method, 0, 1 ) ne q[/] ) {
        if ( $self->{api_ver} ) {
            $method = "/$self->{api_ver}/$method";
        }
        else {
            die qq[You need to defined default "api_ver" to use relative methods names];
        }
    }

    if ( $self->{_is_http} ) {
        $self->_send_http( $method, @args );
    }
    else {
        $self->_send_ws( $method, @args );
    }

    return;
}

sub _send_http ( $self, $method, @ ) {
    my ( $cb, $data );

    # detect callback
    if ( ref $_[-1] eq 'CODE' or ( blessed $_[-1] && $_[-1]->can('IS_CALLBACK') ) ) {
        $cb = $_[-1];

        $data = [ @_[ 2 .. $#_ - 1 ] ] if @_ > 3;
    }
    else {
        $data = [ @_[ 2 .. $#_ ] ] if @_ > 2;
    }

    my $payload = {
        type   => 'rpc',
        method => $method,
        ( $cb   ? ( tid  => uuid_str ) : () ),
        ( $data ? ( data => $data )    : () ),
    };

    P->http->post(
        $self->uri,
        connect_timeout => $self->{connect_timeout},
        persistent      => $self->{persistent},
        tls_ctx         => $self->{tls_ctx},
        ( $self->{timeout} ? ( timeout => $self->{timeout} ) : () ),
        headers => {
            REFERER       => undef,
            AUTHORIZATION => "Token $self->{token}",
            CONTENT_TYPE  => 'application/cbor',
        },
        body      => to_cbor($payload),
        on_finish => sub ($res) {
            if ( !$res ) {
                $cb->( result [ $res->status, $res->reason ] ) if $cb;
            }
            else {
                my $msg = eval { from_cbor $res->body };

                if ($@) {
                    $cb->( result [ 500, 'Error decoding response' ] ) if $cb;
                }
                elsif ($cb) {
                    my $trans = ref $msg eq 'ARRAY' ? $msg->[0] : $msg;

                    if ( $trans->{type} eq 'exception' ) {
                        $cb->( bless $trans->{message}, 'Pcore::Util::Result' );
                    }
                    elsif ( $trans->{type} eq 'rpc' ) {
                        $cb->( bless $trans->{result}, 'Pcore::Util::Result' );
                    }
                }
            }

            return;
        },
    );

    return;
}

sub _send_ws ( $self, @args ) {
    my $cb = ref $_[-1] eq 'CODE' || ( blessed $_[-1] && $_[-1]->can('IS_CALLBACK') ) ? $_[-1] : undef;

    $self->_get_ws(
        sub ( $ws, $error ) {
            if ( defined $error ) {
                $cb->($error) if $cb;
            }
            else {
                $ws->rpc_call(@args);
            }

            return;
        }
    );

    return;
}

sub _get_ws ( $self, $cb ) {
    if ( $self->{_ws} ) {
        $cb->( $self->{_ws}, undef );
    }
    else {
        push $self->{_get_ws_cb}->@*, $cb;

        return if $self->{_get_ws_cb}->@* > 1;

        weaken $self;

        Pcore::WebSocket->connect_ws(
            pcore            => $self->uri,
            max_message_size => 0,
            compression      => $self->{compression},
            connect_timeout  => $self->{connect_timeout},
            tls_ctx          => $self->{tls_ctx},
            ( $self->{token} ? ( headers => [ Authorization => "Token $self->{token}" ] ) : () ),
            before_connect => {

                # listen_events  => $args{listen_events},
                # forward_events => $args{forward_events},
            },
            on_connect_error => sub ($res) {
                while ( my $cb = shift $self->{_get_ws_cb}->@* ) {
                    $cb->( undef, $res );
                }

                return;
            },
            on_connect => sub ( $ws, $headers ) {
                $self->{_ws} = $ws;

                while ( my $cb = shift $self->{_get_ws_cb}->@* ) {
                    $cb->( $ws, undef );
                }

                return;
            },
            on_disconnect => sub ( $ws, $status ) {
                undef $self->{_ws};

                $self->{on_disconnect}->($status) if $self && $self->{on_disconnect};

                return;
            },
            on_rpc => sub ( $ws, $req, $trans ) {
                $self->{on_rpc}->( $ws, $req, $trans ) if $self && $self->{on_rpc};

                return;
            },
        );
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
## |    3 | 77                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
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
