package Pcore::Node;

use Pcore -class, -res, -const;
use Pcore::Util::Scalar qw[weaken refaddr is_ref is_blessed_ref is_plain_coderef is_plain_hashref];
use Pcore::HTTP::Server;
use Pcore::Node::Server;
use Pcore::Node::Proc;
use Pcore::WebSocket::pcore;
use Pcore::Util::UUID qw[uuid_v4_str];

has type     => ( required => 1 );
has server   => ();                  # InstanceOf['Pcore::Node::Server'], $uri, HashRef, if not specified - local server will be created
has listen   => ();
has requires => ();                  # HashRef, required nodes types

has on_status => ();                 # CodeRef, ->($self, $new_status, $old_status)
has on_rpc    => ();                 # CodeRef, ->($self, $req, $tx)
has on_event  => ();                 # CodeRef, ->($self, $ev)

has reconnect_timeout   => 3;
has compression         => 0;         # use websocket compression
has pong_timeout        => 60 * 5;    # for websocket client
has wait_online_timeout => ();        # default wait_online timeout, false - wait forever

has id               => ( sub {uuid_v4_str}, init_arg => undef );    # my node id
has is_online        => ( init_arg                    => undef );    # node online status
has server_is_online => ( init_arg                    => undef );    # node server status
has status           => ( init_arg                    => undef );    # node status

has _has_requires     => ( init_arg => undef );
has _server_is_remote => ( init_arg => undef );
has _remote_server_h  => ( init_arg => undef );                      # remote node server connection handle
has _http_server      => ( init_arg => undef );                      # InstanceOf['Pcore::HTTP::Server']
has _wait_online_cb   => ( init_arg => undef );                      # HashRef, wait online callbacks, callback_id => sub
has _wait_node_cb     => ( init_arg => undef );                      # HashRef, wait node callbacks by node type, callback_id => sub
has _node_proc        => ( init_arg => undef );                      # HashRef, running nodes processes
has _on_rpc           => ( init_arg => undef );                      # on_rpc callback wrapper
has _on_event         => ( init_arg => undef );                      # on_event callback wrapper

# TODO
has _nodes            => ( init_arg => undef );                      # ArrayRef, nodes table
has _connected_nodes  => ( init_arg => undef );                      # HashRef, connected nodes, hashed by id
has _connecting_nodes => ( init_arg => undef );                      # HashRef, connecting / reconnecting nodes
has _ready_nodes      => ( init_arg => undef );                      # HashRef, READY nodes connections by node type
has _online_nodes     => ( init_arg => undef );                      # HashRef, ONLINE nodes connections by node type

const our $NODE_STATUS_UNKNOWN    => -1;
const our $NODE_STATUS_OFFLINE    => 0;                              # blocked
const our $NODE_STATUS_CONNECTING => 1;                              # blocked, connecting to required nodes
const our $NODE_STATUS_CONNECTED  => 2;                              # blocked, connected to the all required nodes
const our $NODE_STATUS_READY      => 3;                              # blocked, CONNECTED and all required nodes are in the CONNECTED state
const our $NODE_STATUS_ONLINE     => 4;                              # unblocked, READY and all required nodes are in the READY or ONLINE state

const our $NODE_STATUS_REASON => {
    $NODE_STATUS_UNKNOWN    => 'unknown',
    $NODE_STATUS_OFFLINE    => 'offline',
    $NODE_STATUS_CONNECTING => 'connecting',
    $NODE_STATUS_CONNECTED  => 'connected',
    $NODE_STATUS_READY      => 'ready',
    $NODE_STATUS_ONLINE     => 'online',
};

sub BUILD ( $self, $args ) {
    $self->{_has_requires} = do {
        if ( !defined $self->{requires} ) {
            undef;
        }
        elsif ( !$self->{requires}->%* ) {
            undef;
        }
        elsif ( keys $self->{requires}->%* == 1 && exists $self->{requires}->{'*'} ) {
            undef;
        }
        else {
            1;
        }
    };

    # resolve listen
    $self->{listen} = P->uri( $self->{listen}, base => 'ws:', listen => 1 ) if !is_ref $self->{listen};

    # generate token
    $self->{listen}->username(uuid_v4_str) if !defined $self->{listen}->{username};

    # init node status
    $self->{status} = $self->{_has_requires} ? $NODE_STATUS_CONNECTING : $NODE_STATUS_ONLINE;
    $self->{is_online} = $self->{status} == $NODE_STATUS_ONLINE ? 1 : 0;

    $self->{on_status}->( $self, $self->{status}, $NODE_STATUS_UNKNOWN ) if defined $self->{on_status};

    $self->{_on_rpc}   = $self->_build__on_rpc;
    $self->{_on_event} = $self->_build__on_event;

    $self->_run_http_server;

    # remote server
    if ( defined $self->{server} && ( !is_ref $self->{server} || ( is_blessed_ref $self->{server} && $self->{server}->isa('Pcore::Util::URI') ) ) ) {
        $self->{_server_is_remote} = 1;
        $self->{server_is_online}  = 0;

        # convert to uri object
        $self->{server} = P->uri( $self->{server}, base => 'ws:' ) if !is_ref $self->{server};

        $self->_connect_to_remote_server;
    }

    # local server
    else {
        $self->{_server_is_remote} = 0;
        $self->{server_is_online}  = 1;

        # create local server if not instance of Pcore::Node::Server
        if ( ref $self->{server} ne 'Pcore::Node::Server' ) {
            $self->{server} = Pcore::Node::Server->new( $self->{server} // () );
        }

        $self->{server}->register_node( $self, $self->{id}, $self->_node_register_data );
    }

    return;
}

sub _node_register_data ($self) {
    return {
        id       => $self->{id},
        type     => $self->{type},
        listen   => $self->{listen},
        status   => $self->{status},
        requires => $self->{requires},
    };
}

sub _connect_to_remote_server ($self) {
    state $RPC_METHOD = {
        _on_node_register => 1,
        _on_node_add      => 1,
        _on_node_update   => 1,
        _on_node_remove   => 1
    };

    weaken $self;

    Coro::async_pool {
        return if !defined $self;

        my $h = Pcore::WebSocket::pcore->connect(
            $self->{server},
            compression   => $self->{compression},
            pong_timeout  => $self->{pong_timeout},
            token         => [ $self->{server}->username, $self->{id}, $self->_node_register_data ],
            on_disconnect => sub ($h) {

                # node was destroyed
                return if !defined $self;

                undef $self->{_remote_server_h};
                $self->{server_is_online} = 0;

                # reconnect to server
                my $t;

                $t = AE::timer $self->{reconnect_timeout}, 0, sub {

                    # node was destroyed
                    return if !defined $self;

                    undef $t;

                    $self->_connect_to_remote_server;

                    return;
                };

                return;
            },
            on_rpc => sub ( $h, $req, $tx ) {

                # node was destroyed
                return if !defined $self;

                if ( exists $RPC_METHOD->{ $tx->{method} } ) {
                    my $method = $tx->{method};

                    $self->$method( $tx->{args}->@* );
                }

                return;
            },
        );

        # connected to the node server
        if ($h) {
            $self->{_remote_server_h} = $h;
            $self->{server_is_online} = 1;
        }

        return;
    };

    return;
}

sub _on_node_register ( $self, $nodes ) {
    for my $node ( $nodes->@* ) {
        $self->_on_node_add( $node, 0 );
    }

    $self->_check_status;

    return;
}

sub _on_node_add ( $self, $node, $check_status = 1 ) {
    my $node_id = $node->{id};

    $self->{_nodes}->{$node_id} = $node;

    # node was already connected, connections status was unknown, events listeners was disabled
    if ( my $conn = $self->{_connected_nodes}->{$node_id} ) {

        # sync status
        $conn->{status} = $node->{status};

        # add connection to the "ready" pool
        if ( $node->{status} == $NODE_STATUS_READY ) {
            $self->_add_ready_conn($conn);
        }

        # add connection to the "online" pool
        elsif ( $node->{status} == $NODE_STATUS_ONLINE ) {
            $self->_add_online_conn($conn);
        }

        $self->_check_status if $check_status;

        $self->_check_wait_node( $node->{type} ) if $self->{_has_requires} && $node->{status} == $NODE_STATUS_ONLINE;
    }

    # node was not connected
    else {

        # try to connect to the remote node
        $self->_connect_node( $node->{id} );
    }

    return;
}

sub _on_node_update ( $self, $node_id, $new_status ) {
    my $node = $self->{_nodes}->{$node_id};

    # set new status
    $node->{status} = $new_status;

    # node was already connected
    if ( my $conn = $self->{_connected_nodes}->{$node_id} ) {
        my $node_type = $node->{type};

        # remove connection from the "ready" pool
        if ( $conn->{status} == $NODE_STATUS_READY ) {
            $self->_remove_ready_conn( $node_id, $node_type );
        }

        # remove connection from the "online" pool
        elsif ( $conn->{status} == $NODE_STATUS_ONLINE ) {
            $self->_remove_online_conn( $node_id, $node_type );
        }

        # sync status
        $conn->{status} = $new_status;

        # add connection to the "ready" pool
        if ( $new_status == $NODE_STATUS_READY ) {
            $self->_add_ready_conn($conn);
        }

        # add connection to the "online" pool
        elsif ( $new_status == $NODE_STATUS_ONLINE ) {
            $self->_add_online_conn($conn);
        }

        $self->_check_status;

        # node status changed to ONLINE
        $self->_check_wait_node( $node->{type} ) if $self->{_has_requires} && $new_status == $NODE_STATUS_ONLINE;
    }

    return;
}

sub _on_node_remove ( $self, $node_id ) {

    # remove node from nodes table
    my $node = delete $self->{_nodes}->{$node_id};

    # remove node connections
    # because we will not get node status updates anymore
    if ( my $conn = delete $self->{_connected_nodes}->{$node_id} ) {

        # force disconnect
        $conn->{h}->disconnect;

        # remove connection from the "ready" pool
        if ( $conn->{status} == $NODE_STATUS_READY ) {
            $self->_remove_ready_conn( $node_id, $conn->{type} );
        }

        # remove connection from the "online" pool
        elsif ( $conn->{status} == $NODE_STATUS_ONLINE ) {
            $self->_remove_online_conn( $node_id, $conn->{type} );
        }

        $self->_check_status;
    }

    return;
}

sub _check_status ($self) {
    return if !$self->{_has_requires};

    # do nothing if in OFFLINE
    return if $self->{status} == $NODE_STATUS_OFFLINE;

    my $new_status = $self->_get_status;

    $self->_set_status($new_status);

    return;
}

sub _check_wait_node ( $self, $node_type ) {

    # has no pending "wait_node" callbacks for this type
    return if !exists $self->{_wait_node_cb}->{$node_type};

    my $online_nodes = $self->{_online_nodes}->{$node_type};

    # has no online nodes of this type
    return if !$online_nodes || !$online_nodes->@*;

    # call pending callbacks
    for my $cb ( values delete( $self->{_wait_node_cb}->{$node_type} )->%* ) { $cb->() }

    return;
}

sub _get_status ($self) {
    return $NODE_STATUS_ONLINE if !$self->{_has_requires};

    my ( $processed_type_status, $total_connected_types, $total_status );

    state $READY_ONLINE = 100;

    # for each required and connected node
    # calculate sum of noodes by type
    for my $connection ( values $self->{_connected_nodes}->%* ) {

        # skip not-required nodes
        next if !exists $self->{requires}->{ $connection->{type} };

        # calc READY_ONLINE
        if ( $connection->{status} >= $NODE_STATUS_READY && !$processed_type_status->{ $connection->{type} }->{$READY_ONLINE} ) {
            $processed_type_status->{ $connection->{type} }->{$READY_ONLINE} = 1;

            $total_status->{$READY_ONLINE}++;
        }

        # status for this type is already added
        if ( !exists $processed_type_status->{ $connection->{type} }->{ $connection->{status} } ) {
            $processed_type_status->{ $connection->{type} }->{ $connection->{status} } = 1;

            $total_connected_types++;

            $total_status->{ $connection->{status} }++;
        }
    }

    my $total_required_types = $self->{requires}->%*;

    no warnings qw[uninitialized];

    # CONNECTING - not all required types are connected
    return $NODE_STATUS_CONNECTING if $total_connected_types < $total_required_types;

    # ONLINE - all required types are in READY or ONLINE state
    return $NODE_STATUS_ONLINE if $total_status->{$READY_ONLINE} == $total_required_types;

    # ONLINE - all required types are READY
    return $NODE_STATUS_ONLINE if $total_status->{$NODE_STATUS_READY} == $total_required_types;

    # READY - all required types are CONNECTED
    return $NODE_STATUS_READY if $total_status->{$NODE_STATUS_CONNECTED} == $total_required_types;

    # CONNECTED
    return $NODE_STATUS_CONNECTED;
}

sub _set_status ( $self, $new_status ) {
    my $old_status = $self->{status};

    return if $old_status == $new_status;

    $self->{status} = $new_status;

    # update status on server
    if ( defined $self->{server} && $self->{server_is_online} ) {
        if ( $self->{_server_is_remote} ) { $self->{_remote_server_h}->rpc_call( 'update_status', $new_status ) }
        else                              { $self->{server}->update_node_status( $self->{id}, $new_status ) }
    }

    # call "on_status" callback
    $self->{on_status}->( $self, $new_status, $old_status ) if $self->{on_status};

    if ( $new_status != $NODE_STATUS_ONLINE ) {
        $self->{is_online} = 0;
    }
    else {
        $self->{is_online} = 1;

        # status was changed to "online" and has "wait_online" callbacks
        if ( $self->{_wait_online_cb} ) {

            # call pending "wait_for_online" callbacks
            for my $cb ( values delete( $self->{_wait_online_cb} )->%* ) { $cb->() }
        }
    }

    return;
}

sub go_online ($self) {
    return if $self->{status} != $NODE_STATUS_OFFLINE;

    my $new_status = $self->_get_status;

    $self->_set_status($new_status);

    return;
}

sub go_offline ($self) {
    return if $self->{status} == $NODE_STATUS_OFFLINE;

    $self->_set_status($NODE_STATUS_OFFLINE);

    return;
}

# TODO on_bind
sub _run_http_server ($self) {
    weaken $self;

    $self->{_http_server} = Pcore::HTTP::Server->new(
        listen     => $self->{listen},
        on_request => sub ($req) {
            if ( $req->is_websocket_connect_request ) {
                my $h = Pcore::WebSocket::pcore->accept(
                    $req,
                    compression   => $self->{compression},
                    on_disconnect => sub ($h) {

                        # node was destroyed
                        return if !defined $self;

                        $self->_on_node_disconnect($h);

                        return;
                    },
                    on_auth => sub ( $h, $token ) {

                        # node was destroyed
                        return if !defined $self;

                        ( $token, $h->{node_id}, $h->{node_type} ) = $token->@*;

                        if ( exists $self->{_connecting_nodes}->{ $h->{node_id} } && $h->{node_id} le $self->{id} ) {
                            $h->disconnect;

                            return;
                        }
                        elsif ( defined $self->{listen}->{username} && $token ne $self->{listen}->{username} ) {
                            $h->disconnect;

                            return;
                        }
                        else {
                            return res(200), $self->_get_bindings( $h->{node_type} );
                        }
                    },
                    on_ready => sub ($h) {

                        # node was destroyed
                        return if !defined $self;

                        $self->_on_node_connect($h);

                        return;
                    },

                    # TODO
                    on_bind  => sub ( $h, $binding ) { return 1 },
                    on_event => $self->{_on_event},
                    on_rpc   => $self->{_on_rpc},
                );
            }

            return;
        }
    );

    return;
}

sub _can_connect_node ( $self, $node_id, $check_connecting = 1 ) {

    # check, that node is known
    my $node = $self->{_nodes}->{$node_id};

    # return if node is unknown (was removed from nodes table)
    return if !defined $node;

    # node is already connected
    return if exists $self->{_connected_nodes}->{$node_id};

    # node is already in connecting phase
    return if $check_connecting && exists $self->{_connecting_nodes}->{$node_id};

    return $node;
}

# TODO on_bind
sub _connect_node ( $self, $node_id, $check_connecting = 1 ) {
    my $node = $self->_can_connect_node( $node_id, $check_connecting );

    # can't connect to the node
    return if !defined $node;

    # mark node as connecting
    $self->{_connecting_nodes}->{$node_id} = 1;

    $node->{listen} = P->uri( $node->{listen}, base => 'ws:' ) if !is_ref $node->{listen};

    weaken $self;

    Coro::async_pool {
        my $h = Pcore::WebSocket::pcore->connect(
            $node->{listen},
            compression   => $self->{compression},
            pong_timeout  => $self->{pong_timeout},
            token         => [ $node->{listen}->username, $self->{id}, $self->{type} ],
            bindings      => $self->_get_bindings( $node->{type} ) // undef,
            node_id       => $node_id,
            node_type     => $node->{type},
            on_disconnect => sub ($h) {

                # node was destroyed
                return if !defined $self;

                $self->_on_node_disconnect($h);

                # can't connect to the node
                if ( !defined $self->_can_connect_node( $node_id, 0 ) ) {

                    # remove node from connecting nodes
                    delete $self->{_connecting_nodes}->{$node_id};

                    return;
                }

                # reconnect to node
                my $t;

                $t = AE::timer $self->{reconnect_timeout}, 0, sub {
                    undef $t;

                    # node was destroyed
                    return if !defined $self;

                    $self->_connect_node( $node_id, 0 );

                    return;
                };

                return;
            },

            # TODO
            on_bind  => sub ( $h, $binding ) { return 1 },
            on_event => $self->{_on_event},
            on_rpc   => $self->{_on_rpc},
        );

        # connected to the node server
        if ($h) {

            # remove node from connecting nodes
            delete $self->{_connecting_nodes}->{$node_id};

            # do not store connection if node was removed during connecting
            # because we can't get node status updates
            $self->_on_node_connect($h) if exists $self->{_nodes}->{$node_id};
        }

        return;
    };

    return;
}

sub _get_bindings ( $self, $node_type ) {
    return if !defined $self->{on_event};

    if ( defined( my $requires = $self->{requires} ) ) {
        return $requires->{$node_type} if exists $requires->{$node_type};

        return $requires->{'*'} if exists $requires->{'*'};
    }

    return;
}

sub _build__on_rpc ($self) {
    return if !defined $self->{on_rpc};

    weaken $self;

    return sub ( $h, $req, $tx ) {
        if ( !defined $self ) {
            $req->( [ 1013, 'Node Destroyed' ] );
        }
        elsif ( $self->{status} < $NODE_STATUS_READY ) {
            $req->( [ 1013, 'Node is Offline' ] );
        }
        else {
            $self->{on_rpc}->( $self, $req, $tx );
        }

        return;
    };
}

sub _build__on_event ($self) {
    return if !defined $self->{on_event};

    weaken $self;

    return sub ( $h, $ev ) {
        return if !defined $self;

        if ( $self->{status} >= $NODE_STATUS_READY ) {
            $self->{on_event}->( $self, $ev );
        }

        return;
    };
}

sub _on_node_connect ( $self, $h ) {
    my $node_id   = $h->{node_id};
    my $node_type = $h->{node_type};

    my $node = $self->{_nodes}->{$node_id};

    # get / add new node connection
    my $conn = $self->{_connected_nodes}->{$node_id} //= {
        id     => $node_id,
        type   => $node_type,
        status => $NODE_STATUS_UNKNOWN,
        h      => $h,
    };

    # node is exists in the nodes table, node status is known
    if ( defined $node ) {

        # set connection status
        $conn->{status} = $node->{status};

        # add connection to the "ready" pool
        if ( $node->{status} == $NODE_STATUS_READY ) {
            $conn->{h}->suspend_events;

            $self->_add_ready_conn($conn);
        }

        # add connection to the "online" pool
        elsif ( $node->{status} == $NODE_STATUS_ONLINE ) {
            $self->_add_online_conn($conn);
        }
        else {

            # suspend events listener
            $h->suspend_events;
        }

        $self->_check_status;

        $self->_check_wait_node($node_type) if $self->{_has_requires} && $node->{status} == $NODE_STATUS_ONLINE;
    }

    # node status unknown
    else {

        # suspend events listener
        $h->suspend_events;
    }

    return;
}

sub _on_node_disconnect ( $self, $h ) {
    my $node_id = $h->{node_id};

    my $conn = $self->{_connected_nodes}->{$node_id};

    # node was connected, and handle id is match connected node handle id
    if ( defined $conn && $conn->{h}->{id} eq $h->{id} ) {
        delete $self->{_connected_nodes}->{$node_id};

        # remove connection from the "ready" pool
        if ( $conn->{status} == $NODE_STATUS_READY ) {
            $self->_remove_ready_conn( $node_id, $conn->{type} );
        }

        # remove connection from the "online" pool
        elsif ( $conn->{status} == $NODE_STATUS_ONLINE ) {
            $self->_remove_online_conn( $node_id, $conn->{type} );
        }

        # re-check status
        $self->_check_status;
    }

    return;
}

sub _add_ready_conn ( $self, $conn ) {

    # add node connection to the ready pool
    unshift $self->{_ready_nodes}->{ $conn->{type} }->@*, $conn->{h};

    return;
}

sub _remove_ready_conn ( $self, $node_id, $node_type ) {
    my $pool = $self->{_ready_nodes}->{$node_type};

    # remove node from online nodes
    for ( my $i = 0; $i <= $pool->$#*; $i++ ) {
        if ( $pool->[$i]->{node_id} eq $node_id ) {
            splice $pool->@*, $i, 1;

            last;
        }
    }

    return;
}

sub _add_online_conn ( $self, $conn ) {

    # resume events listener
    $conn->{h}->resume_events;

    # add node connection to the online pool
    unshift $self->{_online_nodes}->{ $conn->{type} }->@*, $conn->{h};

    return;
}

sub _remove_online_conn ( $self, $node_id, $node_type ) {
    my $pool = $self->{_online_nodes}->{$node_type};

    # remove node from online nodes
    for ( my $i = 0; $i <= $pool->$#*; $i++ ) {
        if ( $pool->[$i]->{node_id} eq $node_id ) {
            splice $pool->@*, $i, 1;

            # suspend events listener
            $pool->[$i]->suspend_events;

            last;
        }
    }

    return;
}

sub online_nodes ( $self, $type ) {
    return 0 if !$self->{_online_nodes}->{$type};

    return scalar $self->{_online_nodes}->{$type}->@*;
}

sub wait_online ( $self, $timeout = undef ) {
    return 1 if $self->{is_online};

    my $cv = P->cv;

    my $id = refaddr $cv;

    $self->{_wait_online_cb}->{$id} = $cv;

    # set timer if has $timeout
    my $t;

    if ( $timeout //= $self->{wait_online_timeout} ) {
        $t = AE::timer $timeout, 0, sub {

            # node was destroyed
            return if !defined $self;

            # remove and call callback
            ( delete $self->{_wait_online_cb}->{$id} )->();

            return;
        };
    }

    $cv->recv;

    return $self->{is_online};
}

sub wait_node ( $self, $type, $timeout = undef ) {

    # only required nodes can be monitored
    return if !$self->{_has_requires} || !exists $self->{requires}->{$type};

    my $online_nodes = $self->online_nodes($type);

    return $online_nodes if $online_nodes;

    my $cv = P->cv;

    my $id = refaddr $cv;

    $self->{_wait_node_cb}->{$type}->{$id} = $cv;

    # set timer if has $timeout
    my $t;

    if ( $timeout //= $self->{wait_online_timeout} ) {
        $t = AE::timer $timeout, 0, sub {

            # node was destroyed
            return if !defined $self;

            # remove and call callback
            ( delete $self->{_wait_node_cb}->{$type}->{$id} )->();

            return;
        };
    }

    $cv->recv;

    return $self->online_nodes($type);
}

# required for run node via run_proc interface
sub import {
    if ( $0 eq '-' ) {
        state $init;

        return if $init;

        $init = 1;

        my ( $self, $type ) = @_;

        # read and unpack boot args from STDIN
        my $RPC_BOOT_ARGS = <>;

        chomp $RPC_BOOT_ARGS;

        require CBOR::XS;

        $RPC_BOOT_ARGS = CBOR::XS::decode_cbor( pack 'H*', $RPC_BOOT_ARGS );

        # init RPC environment
        $Pcore::SCRIPT_PATH = $RPC_BOOT_ARGS->{script_path};
        $main::VERSION      = version->new( $RPC_BOOT_ARGS->{version} );

        require Pcore::Node::Node;

        require $type =~ s[::][/]smgr . '.pm';

        Pcore::Node::Node::run( $type, $RPC_BOOT_ARGS );

        exit;
    }

    return;
}

sub run_node ( $self, @nodes ) {
    my $cv = P->cv->begin;

    weaken $self;

    my $cpus_num = P->sys->cpus_num;

    my $server = do {
        if ( ref $self->{server} eq 'Pcore::Node::Server' ) {
            $self->{server}->{listen};
        }
        else {
            $self->{server};
        }
    };

    for my $node (@nodes) {

        # resolve number of the workers
        if ( !$node->{workers} ) {
            $node->{workers} = $cpus_num;
        }
        elsif ( $node->{workers} < 0 ) {
            $node->{workers} = P->sys->cpus_num - $node->{workers};

            $node->{workers} = 1 if $node->{workers} <= 0;
        }

        # run workers
        for ( 1 .. $node->{workers} ) {
            $cv->begin;

            Coro::async_pool {
                my $node_proc = Pcore::Node::Proc->new(
                    $node->{type},
                    server    => $node->{server} // $server,
                    listen    => $node->{listen},
                    buildargs => $node->{buildargs},
                    on_finish => sub ($proc) {
                        return if !defined $self;

                        delete $self->{_node_proc}->{ refaddr $proc };

                        return;
                    }
                );

                $self->{_node_proc}->{ refaddr $node_proc} = $node_proc;

                $cv->end;

                return;
            };
        }
    }

    $cv->end->recv;

    return res 200;
}

# TODO repeat to other node if node returns 1013 Try Again Later
sub rpc_call ( $self, $type, $method, @args ) {
    my $h = shift $self->{_online_nodes}->{$type}->@*;

    if ( defined $h ) {
        push $self->{_online_nodes}->{$type}->@*, $h;
    }
    else {
        $h = shift $self->{_ready_nodes}->{$type}->@*;

        push $self->{_ready_nodes}->{$type}->@*, $h if defined $h;
    }

    if ( !defined $h ) {
        my $res = res [ 404, qq[Node type "$type" is not available] ];

        my $cb = is_plain_coderef $args[-1] || ( is_blessed_ref $args[-1] && $args[-1]->can('IS_CALLBACK') ) ? pop @args : undef;

        return $cb ? $cb->($res) : $res;
    }

    return $h->rpc_call( $method, @args );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 |                      | Subroutines::ProhibitUnusedPrivateSubroutines                                                                  |
## |      | 203                  | * Private subroutine/method '_on_node_register' declared but not used                                          |
## |      | 249                  | * Private subroutine/method '_on_node_update' declared but not used                                            |
## |      | 291                  | * Private subroutine/method '_on_node_remove' declared but not used                                            |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 749, 775             | ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Node

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
