package Pcore::WebSocket::pcore;

use Pcore -class, -const, -res;
use Pcore::Lib::Data qw[to_b64];
use Pcore::Lib::UUID qw[uuid_v1mc_str];
use Pcore::Lib::Scalar qw[is_res weaken is_plain_arrayref is_plain_coderef];
use Clone qw[];

with qw[Pcore::WebSocket::Handle];

# client attributes
has token    => ();    # authentication token, used on client only
has bindings => ();    # events bindings, used on client only

# callbacks
has on_disconnect => ();    # Maybe [CodeRef], ($self)
has on_auth       => ();    # Maybe [CodeRef], server only: ($self, $token), called synchronously
has on_bind       => ();    # Maybe [CodeRef], ($self, $bindings), must return true to allow bind event
has on_event      => ();    # Maybe [CodeRef], ($self, $ev)
has on_rpc        => ();    # Maybe [CodeRef], ($self, $tx)

has auth          => ( init_arg             => undef );
has _auth_cb      => ( init_arg             => undef );    # client only
has _rpc_cb       => ( sub { {} }, init_arg => undef );    # HashRef, tid => $cb
has _peer_is_text => ( init_arg             => undef );    # remote peer message serialization protocol
has _listener     => ( init_arg             => undef );    # ConsumerOf['Pcore::Core::Event::Listener']

const our $PROTOCOL => 'pcore';

const our $TX_TYPE_AUTH  => 'auth';
const our $TX_TYPE_EVENT => 'event';
const our $TX_TYPE_RPC   => 'rpc';

my $CBOR = Pcore::Lib::Data::get_cbor();
my $JSON = Pcore::Lib::Data::get_json( utf8 => 1 );

sub rpc_call ( $self, $method, @args ) {
    my $msg = {
        type   => $TX_TYPE_RPC,
        method => $method,
        args   => \@args,
    };

    if ( defined wantarray ) {
        my $cv = $self->{_rpc_cb}->{ $msg->{tid} = uuid_v1mc_str } = P->cv;

        $self->_send_msg($msg);

        return $cv->recv;
    }
    else {
        $self->_send_msg($msg);

        return;
    }
}

sub auth ( $self, $token, $bindings = undef ) {
    $self->_reset;

    $self->{token}    = $token;
    $self->{bindings} = $bindings;

    my $cv = $self->{_auth_cb} = P->cv;

    $self->_send_msg( {
        type     => $TX_TYPE_AUTH,
        token    => $token,
        bindings => $bindings,
    } );

    $cv->recv;

    return $self;
}

sub _on_connect ($self) {

    # create events listener
    $self->_create_listener;

    # authenticate automatically
    if ( $self->{_is_client} ) {
        return $self->auth( $self->{token}, $self->{bindings} );
    }
    else {
        return $self;
    }
}

sub _on_disconnect ( $self ) {
    $self->_reset( res [ $self->{status}, $self->{reason} ] );

    $self->{on_disconnect}->($self) if $self->{on_disconnect};

    return;
}

sub _on_text ( $self, $data_ref ) {
    my $msg = eval { $JSON->decode( $data_ref->$* ) };

    # unable to decode message
    return if $@;

    $self->{_peer_is_text} //= 1;

    $self->_on_message($msg);

    return;
}

sub _on_binary ( $self, $data_ref ) {
    my $msg = eval { $CBOR->decode( $data_ref->$* ) };

    # unable to decode message
    return if $@;

    $self->{_peer_is_text} //= 0;

    $self->_on_message($msg);

    return;
}

sub _on_message ( $self, $msg ) {
    for my $tx ( is_plain_arrayref $msg ? $msg->@* : $msg ) {

        # skip, if transaction type is not defined
        next if !$tx->{type};

        # AUTH
        if ( $tx->{type} eq $TX_TYPE_AUTH ) {

            # auth response, processed on client only
            if ( $self->{_is_client} ) {
                $self->_on_auth_response($tx);
            }

            # auth request, processed on server only
            else {
                $self->_on_auth_request($tx);
            }
        }

        # EVENT
        if ( $tx->{type} eq $TX_TYPE_EVENT ) {
            $self->{on_event}->( $self, $tx->{event} ) if $self->{on_event};
        }

        # RPC
        elsif ( $tx->{type} eq $TX_TYPE_RPC ) {

            # method is specified, this is rpc call
            if ( $tx->{method} ) {

                # RPC calls are not supported by this peer
                if ( !$self->{on_rpc} ) {
                    if ( $tx->{tid} ) {
                        $self->_send_msg( {
                            type   => $TX_TYPE_RPC,
                            tid    => $tx->{tid},
                            result => {
                                status => 400,
                                reason => 'RPC calls are not supported',
                            }
                        } );
                    }
                }

                # RPC call
                else {
                    Coro::async_pool sub ($tx) {
                        my @res = eval { $self->{on_rpc}->( $self, $tx ) };

                        $@->sendlog if $@;

                        # response is required
                        if ( my $tid = $tx->{tid} ) {
                            $self->_send_msg( {
                                type   => $TX_TYPE_RPC,
                                tid    => $tid,
                                result => $@ || !@res ? res 500 : is_res $res[0] ? $res[0] : res @res,
                            } );
                        }

                        return;
                    }, $tx;
                }
            }

            # method is not specified, this is RPC response, tid is required
            elsif ( $tx->{tid} ) {
                if ( my $cb = delete $self->{_rpc_cb}->{ $tx->{tid} } ) {

                    # convert result to response object
                    $cb->( bless $tx->{result}, 'Pcore::Lib::Result::Class' );
                }
            }
        }
    }

    return;
}

# server, auth request
sub _on_auth_request ( $self, $tx ) {
    $self->_reset;

    if ( $self->{on_auth} ) {
        my ( $auth, $bindings ) = $self->{on_auth}->( $self, $tx->{token} );

        # store authentication result
        $self->{auth} = $auth;

        # subscribe client to the server events from client request
        $self->_bind_events( $tx->{bindings} ) if defined $tx->{bindings};

        $self->_send_msg( {
            type     => $TX_TYPE_AUTH,
            auth     => $auth,
            bindings => $bindings,
        } );
    }

    # auth is not supported, reject
    else {
        $self->{auth} = undef;

        $self->_send_msg( {
            type => $TX_TYPE_AUTH,
            auth => {
                status => 401,
                reason => 'Unauthorized',
            }
        } );
    }

    return;
}

# client, auth response
sub _on_auth_response ( $self, $tx ) {

    # create and store auth object
    $self->{auth} = bless $tx->{auth}, 'Pcore::Lib::Result::Class';

    # set events listeners
    $self->_bind_events( $tx->{bindings} ) if defined $tx->{bindings};

    # call on_auth
    if ( my $cb = delete $self->{_auth_cb} ) { $cb->() }

    return;
}

sub _bind_events ( $self, $bindings ) {

    # process bindings if has "on_bind" callback defined
    if ( my $cb = $self->{on_bind} ) {
        for my $binding ( is_plain_arrayref $bindings ? $bindings->@* : $bindings ) {
            next if !defined $binding;

            # already bound
            next if exists $self->{_listener}->{bindings}->{$binding};

            $self->{_listener}->bind($binding) if $cb->( $self, $binding );
        }
    }

    return;
}

sub _reset ( $self, $status = undef ) {
    delete $self->{auth};

    # reset events listener
    $self->{_listener}->unbind_all if defined $self->{_listener};

    # call pending callbacks
    if ( $self->{_rpc_cb}->%* ) {

        # 1012 Service Restart
        $status = res [ 1012, $Pcore::WebSocket::Handle::WEBSOCKET_STATUS_REASON ] if !defined $status;

        for my $tid ( keys $self->{_rpc_cb}->%* ) {
            my $cb = delete $self->{_rpc_cb}->{$tid};

            $cb->( Clone::clone($status) );
        }
    }

    # call auth callback
    if ( my $cb = delete $self->{_auth_cb} ) { $cb->() }

    return;
}

sub _send_msg ( $self, $msg ) {
    if ( $self->{_peer_is_text} ) {
        $self->send_text( \$JSON->encode($msg) );
    }
    else {
        $self->send_binary( \$CBOR->encode($msg) );
    }

    return;
}

sub _create_listener ($self) {
    weaken $self;

    $self->{_listener} = P->ev->bind_events(
        undef,
        sub ($ev) {
            return if !defined $self;

            $self->_send_msg( {
                type  => $TX_TYPE_EVENT,
                event => $ev,
            } );

            return;
        }
    );

    return;
}

sub suspend_events ($self) {
    $self->{_listener}->suspend;

    return;
}

sub resume_events ($self) {
    $self->{_listener}->resume;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 |                      | Subroutines::ProhibitUnusedPrivateSubroutines                                                                  |
## |      | 77                   | * Private subroutine/method '_on_connect' declared but not used                                                |
## |      | 91                   | * Private subroutine/method '_on_disconnect' declared but not used                                             |
## |      | 99                   | * Private subroutine/method '_on_text' declared but not used                                                   |
## |      | 112                  | * Private subroutine/method '_on_binary' declared but not used                                                 |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 125                  | Subroutines::ProhibitExcessComplexity - Subroutine "_on_message" with high complexity score (21)               |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::WebSocket::pcore

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
