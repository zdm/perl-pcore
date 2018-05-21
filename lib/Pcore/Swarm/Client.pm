package Pcore::Swarm::Client;

use Pcore -class, -res;
use Pcore::Util::UUID qw[uuid_v4_str];
use Pcore::Util::Scalar qw[weaken is_blessed_ref is_plain_coderef];
use Pcore::Websocket::Protocol::pcore;
use Pcore::Swarm::Const qw[:ALL];
use Pcore::HTTP::Server;

has swarm => ( required => 1 );    # [$addr, $token], swarm service discovery credentials

has type             => ( required => 1 );    # node type, can be undef for client-only nodes
has is_service       => 0;                    # this node provides services
has listen           => ();                   # will be set automatically for service
has requires         => ();                   # ArrayRef, list of nodes types, required by this node to start
has forward_events   => ();
has subscribe_events => ();
has on_subscribe     => ();                   # CodeRef
has on_event         => ();                   # CodeRef
has on_rpc           => ();                   # CodeRef

has id                     => sub {uuid_v4_str};    # this node id
has is_online              => 0;                    # Bool, online status
has _token                 => sub {uuid_v4_str};    # this node token
has _swarm                 => ();                   # connection to the swarm
has _requires              => ();                   # HashRef, type => $num_of_connecetions
has _node_by_id            => ();                   # HashRef, index of nodes connections by node id
has _node_by_type          => ();                   # HashRef[ArrayRef], index of nodes connections by node type
has _http_svr              => ();                   # HTTP server object
has _wait_for_online_queue => ();                   # ArrayRef, wait_for_onliine callbacks
has _wait_for_queue        => ();                   # HashRef

# TODO pass swarm as object - use local method calls
# TODO reconnect to swarn on timeout

sub run ($self) {
    $self->{_requires} = $self->{requires} ? { map { $_ => 0 } $self->{requires}->@* } : {};

    $self->{is_online} = $self->{_requires}->%* ? 0 : 1;

    if ( $self->{is_service} ) {
        $self->{listen} = P->net->resolve_listen( $self->{listen} );

        $self->{_http_svr} = Pcore::HTTP::Server->new( {
            listen => $self->{listen},
            app    => sub ($req) {
                if ( $req->is_websocket_connect_request ) {

                    # create connection
                    my $c = Pcore::WebSocket::Protocol::pcore->new(
                        compression => 0,
                        on_auth     => sub ( $h, $token, $cb ) {

                            # compare tokens
                            if ( ( $token // q[] ) ne $self->{_token} ) {
                                $h->disconnect( res [401] );

                                return;
                            }

                            $cb->( res(200), forward => $self->{forward_events}, subscribe => $self->{subscribe_events} );

                            return;
                        },
                        on_subscribe => $self->{on_subscribe},
                        on_event     => $self->{on_event},
                        on_rpc       => $self->{on_rpc},
                    );

                    # accept websocket connect request
                    $c->accept($req);
                }
                else {
                    $req->return_xxx(400);
                }

                return;
            },
        } )->run;
    }

    # connect to swarm
    $self->{_swarm} = Pcore::WebSocket::Protocol::pcore->new(
        compression => 1,
        token       => [ $self->{id}, $self->{swarm}->[1] ],

        # TODO reconnect to swarm on timeout
        on_disconnect => sub ( $h, $status ) {
            return;
        },
        on_auth => sub ( $h, $auth ) {
            $self->_on_connect_to_swarm;

            return;
        },
        on_subscribe => sub ( $h, $event ) {
            return;
        },
        on_event => sub ( $h, $ev ) {
            $self->_on_swarm_event($ev);

            return;
        },
        on_rpc => sub ( $h, $req, $tx ) {
            return;
        },
    );

    # TODO swarm addr format??
    $self->{_swarm}->connect("ws://$self->{swarm}->[0]/");

    return $self;
}

sub _on_connect_to_swarm ($self) {

    # register on swarm
    $self->{_swarm}->rpc_call(
        'register',
        [ { id         => $self->{id},
            type       => $self->{type},
            token      => $self->{is_service} && $self->{_token},
            is_service => $self->{is_service},
            listen     => $self->{is_service} && $self->{listen},
            status     => $self->{is_online} ? $STATUS_ONLINE : $STATUS_OFFLINE,
        } ],
        sub ($res) {
            $self->_on_nodes_update( $res->{data} ) if $res;

            return;
        }
    );

    return;
}

sub _on_swarm_event ( $self, $ev ) {
    $self->_on_nodes_update( [ $ev->{data} ] );

    return;
}

sub _on_nodes_update ( $self, $nodes ) {
    for my $node ( $nodes->@* ) {

        # next, if this node type is not required
        next if !exists $self->{_requires}->{ $node->{type} };

        # node is available
        if ( $node->{status} == $STATUS_ONLINE ) {

            # next, if already connected to this node
            next if exists $self->{_node_by_id}->{ $node->{id} };

            $self->{_node_by_id}->{ $node->{id} } = $node;

            weaken $self;

            # establish connection to this node
            $node->{h} = Pcore::WebSocket::Protocol::pcore->new(
                token            => $node->{token},
                forward_events   => $self->{forward_events},
                subscribe_events => $self->{subscribe_events},
                compression      => 1,
                pong_timeout     => 60 * 10,
                on_disconnect    => sub ( $h, $status ) {
                    return if !$self;

                    # disconnect node
                    $self->_on_node_disconnect( $h->{node_id} );

                    return;
                },
                on_auth => sub ( $h, $auth ) {
                    return if !$self;

                    push $self->{_node_by_type}->{ $h->{node_type} }->@*, $h;

                    # increase number of connections to this node type
                    $self->{_requires}->{ $h->{node_type} }++;

                    $self->_check_status;

                    return;
                },
                on_subscribe => $self->{on_subscribe},
                on_event     => $self->{on_event},
                on_rpc       => $self->{on_rpc},

                node_id   => $node->{id},
                node_type => $node->{type},
            );

            $node->{h}->connect("ws://$node->{listen}/");
        }

        # node is not available
        elsif ( $node->{status} == $STATUS_OFFLINE ) {

            # disconnect node, if was connected
            $self->{_node_by_id}->{ $node->{id} }->{h}->disconnect if exists $self->{_node_by_id}->{ $node->{id} };
        }
    }

    return;
}

sub _on_node_disconnect ( $self, $node_id ) {

    # node was connected
    if ( my $node = delete $self->{_node_by_id}->{$node_id} ) {
        my $node_by_type = $self->{_node_by_type}->{ $node->{type} };

        # find and remove node connection by type
        for ( my $i = 0; $i <= $node_by_type->$#*; $i++ ) {
            if ( $node_by_type->[$i]->{node_id} eq $node_id ) {
                splice $node_by_type->@*, $i, 1, ();

                last;
            }
        }

        # decrease number of connections to this node type
        $self->{_requires}->{ $node->{type} }--;

        $self->_check_status;
    }

    return;
}

sub _check_status ( $self ) {
    my $is_online = 1;
    my $require   = $self->{_requires};

    for my $require ( values $require->%* ) {
        if ( !$require ) {
            $is_online = 0;

            last;
        }
    }

    if ( $self->{is_online} != $is_online ) {
        $self->{is_online} = $is_online;

        $self->{_swarm}->rpc_call( 'update', [ { status => $is_online ? $STATUS_ONLINE : $STATUS_OFFLINE } ], undef );

        if ($is_online) {

            # process wait_for_online queue
            while ( my $cb = shift $self->{_wait_for_online_queue}->@* ) {
                $cb->();
            }
        }

        # process wait_for queue
      CONDITION: for my $cond ( values $self->{_wait_for_queue}->%* ) {
            for ( $cond->{type}->@* ) {
                next CONDITION if !$require->{$_};
            }

            for my $cb ( $cond->{cb}->@* ) {
                $cb->();
            }

            delete $self->{_wait_for_queue}->{ $cond->{key} };
        }
    }

    return;
}

sub wait_for_online ($self) {
    return if $self->{is_online};

    my $rouse_cb = Coro::rouse_cb;

    push $self->{_wait_for_online_queue}->@*, $rouse_cb;

    return Coro::rouse_wait $rouse_cb;
}

sub wait_for ( $self, @types ) {
    my $is_true = 1;

    for my $type (@types) {
        if ( !$self->{_requires}->{$type} ) {
            $is_true = 0;

            last;
        }
    }

    return if $is_true;

    my $rouse_cb = Coro::rouse_cb;

    my $key = join '-', sort @types;

    if ( exists $self->{_wait_for_queue}->{$key} ) {
        push $self->{_wait_for_queue}->{$key}->{cb}->@*, $rouse_cb;
    }
    else {
        $self->{_wait_for_queue}->{$key} = {
            key  => $key,
            type => \@types,
            cb   => [$rouse_cb],
        };
    }

    return Coro::rouse_wait $rouse_cb;
}

sub rpc_call ( $self, $type, $method, @args ) {
    my $cb = is_plain_coderef $args[-1] || ( is_blessed_ref $args[-1] && $args[-1]->can('IS_CALLBACK') ) ? pop @args : undef;

    my $h = shift $self->{_node_by_type}->{$type}->@*;

    if ( !defined $h ) {
        my $res = res [ 404, qq[Node type "$type" is not available] ];

        return $cb ? $cb->($res) : $res;
    }

    push $self->{_node_by_type}->{$type}->@*, $h;

    if ( defined wantarray ) {
        $h->rpc_call( $method, \@args, my $rouse_cb = Coro::rouse_cb );

        # block
        my $res = Coro::rouse_wait $rouse_cb;

        return $cb ? $cb->($res) : $res;
    }
    else {
        $h->rpc_call( $method, \@args, $cb );

        return;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 215                  | ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Swarm::Client

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
