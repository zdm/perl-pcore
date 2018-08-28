package Pcore::Node;

use Pcore -class, -res;
use Pcore::Util::Scalar qw[weaken refaddr is_ref is_blessed_ref is_plain_coderef];
use Pcore::HTTP::Server;
use Pcore::Node::Server;
use Pcore::Node::Proc;
use Pcore::WebSocket::pcore;
use Pcore::Util::UUID qw[uuid_v4_str];

has type     => ( required => 1 );
has server   => ();                  # InstanceOf['Pcore::Node::Server'] || $uri, if not specified - local server will be created
has listen   => ();
has requires => ();                  # HashRef, required nodes types

has on_status_change => ();          # CodeRef, ->($self, $is_online)
has on_rpc           => ();          # CodeRef, ->($self, $req, $tx)
has on_event         => ();          # CodeRef, ->($self, $ev)

has reconnect_timeout   => 3;
has compression         => 0;         # use websocket compression
has pong_timeout        => 60 * 5;    # for websocket client
has wait_online_timeout => ();        # default wait_online timeout, false - wait forever

has id               => ( sub {uuid_v4_str}, init_arg => undef );    # my node id
has is_online        => ( init_arg                    => undef );    # node status
has server_is_online => ( init_arg                    => undef );    # node server status
has token            => ( init_arg                    => undef );    # from listen uri, generated automatically if not defined

has _has_requires     => ( init_arg => undef );
has _server_is_remote => ( init_arg => undef );
has _remote_server_h  => ( init_arg => undef );                      # remote node server connection handle
has _http_server      => ( init_arg => undef );                      # InstanceOf['Pcore::HTTP::Server']
has _wait_online_cb   => ( init_arg => undef );                      # HashRef, wait online callbacks, callback_id => sub
has _wait_node_cb     => ( init_arg => undef );                      # HashRef, wait node callbacks by node type, callback_id => sub
has _nodes            => ( init_arg => undef );                      # ArrayRef, nodes table
has _connected_nodes  => ( init_arg => undef );                      # HashRef, connected nodes
has _connecting_nodes => ( init_arg => undef );                      # HashRef, connecting / reconnecting nodes
has _online_nodes     => ( init_arg => undef );                      # HashRef, online nodes connections by node type
has _node_proc        => ( init_arg => undef );                      # HashRef, running nodes processes
has _node_data        => ( init_arg => undef );                      # node connect data
has _on_rpc           => ( init_arg => undef );                      # on_rpc callback wrapper
has _on_event         => ( init_arg => undef );                      # on_event callback wrapper

# if node is offline it:
# - can send rpc calls and events to other online nodes;
# - can't receive rps call and events;

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
    $self->{listen} = P->net->resolve_listen( $self->{listen}, 'ws:' ) if !is_ref $self->{listen};

    $self->{token} = $self->{listen}->username || P->uuid->uuid_v4_str;

    # init node status
    $self->{is_online} = $self->{_has_requires} ? 0 : 1;

    $self->{on_status_change}->( $self, $self->{is_online} ) if defined $self->{on_status_change};

    $self->{_on_rpc}   = $self->_build__on_rpc;
    $self->{_on_event} = $self->_build__on_event;

    $self->_run_http_server;

    if ( defined $self->{server} ) {

        # local server
        if ( ref $self->{server} eq 'Pcore::Node::Server' ) {
            $self->{_server_is_remote} = 0;
            $self->{server_is_online}  = 1;

            $self->{server}->register_node( $self, $self->{id}, $self->_node_data );
        }

        # remote server
        else {
            $self->{_server_is_remote} = 1;
            $self->{server_is_online}  = 0;

            # convert to uri object
            $self->{server} = P->uri( $self->{server}, base => 'ws:' ) if !is_ref $self->{server};

            $self->_connect_to_remote_server;
        }
    }

    # create local server instance
    else {
        $self->{server} = Pcore::Node::Server->new;

        $self->{_server_is_remote} = 0;
        $self->{server_is_online}  = 1;

        $self->{server}->register_node( $self, $self->{id}, $self->_node_data );
    }

    return;
}

# TODO use uri method to insert token
sub _node_data ($self) {
    $self->{_node_data} //= do {
        my $listen = $self->{listen};

        # TODO use uri method to insert token
        my $connect = $listen->{scheme} ? "$listen->{scheme}://" : '//';
        $connect .= "$self->{token}@" if defined $self->{token};
        if ( my $host = "$listen->{host}" ) {
            $connect .= "$host:" . $listen->connect_port . '/';
        }
        else {
            $connect .= $listen->{path}->to_string;
        }

        {   id     => $self->{id},
            type   => $self->{type},
            listen => $connect,
        };
    };

    $self->{_node_data}->{is_online} = $self->{is_online};

    return $self->{_node_data};
}

sub _connect_to_remote_server ($self) {
    weaken $self;

    Coro::async_pool {
        return if !defined $self;

        my $h = Pcore::WebSocket::pcore->connect(
            $self->{server},
            compression   => $self->{compression},
            pong_timeout  => $self->{pong_timeout},
            token         => [ $self->{server}->username, $self->{id}, $self->_node_data ],
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

                if ( $tx->{method} eq 'update_node_table' ) {
                    $self->_update_node_table( $tx->{args}->[0] );
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
                        elsif ( $self->{token} && $token ne $self->{token} ) {
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
    )->run;

    return;
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

            $self->_on_node_connect($h);
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
        elsif ( !$self->{is_online} ) {
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

        if ( $self->{is_online} ) {
            $self->{on_event}->( $self, $ev );
        }

        return;
    };
}

sub _can_connect_node ( $self, $node_id, $check_connecting = 1 ) {

    # check, that node is known
    my $node = $self->{_nodes}->{$node_id};

    # return if node is unknown
    return if !defined $node;

    # return if node is not required
    return if !$node->{is_required};

    # node is already connected
    return if exists $self->{_connected_nodes}->{$node_id};

    # node is already in connecting phase
    return if $check_connecting && exists $self->{_connecting_nodes}->{$node_id};

    return $node;
}

sub _on_node_connect ( $self, $h ) {
    my $node_id   = $h->{node_id};
    my $node_type = $h->{node_type};

    my $node = $self->{_nodes}->{$node_id};

    # get / add new node connection
    my $connected_node = $self->{_connected_nodes}->{$node_id} //= {
        h         => $h,
        type      => $node_type,
        is_online => 0,
    };

    # node is known and is online
    if ( defined $node && $node->{is_online} ) {

        # set connection status to online
        $connected_node->{is_online} = $node->{is_online};

        # resume events listener
        $h->resume_events;

        # add node connection to the online list
        unshift $self->{_online_nodes}->{$node_type}->@*, $h;

        # re-check status if node is required
        $self->_check_status if $node->{is_required};
    }

    # node is unknown or is offline
    else {

        # suspend events listener
        $h->suspend_events;
    }

    return;
}

sub _on_node_disconnect ( $self, $h ) {
    my $node_id = $h->{node_id};

    my $connected_node = $self->{_connected_nodes}->{$node_id};

    # node was connected, and handle id is match connected node handle id
    if ( defined $connected_node && $connected_node->{h}->{id} eq $h->{id} ) {

        # remove node from all nodes
        delete $self->{_connected_nodes}->{$node_id};

        # node was online
        if ( $connected_node->{is_online} ) {

            # remove node from online nodes
            $self->_remove_online_node( $node_id, $connected_node->{type} );

            # re-check status if node is required
            $self->_check_status if $self->{_has_requires} && exists $self->{requires}->{ $connected_node->{type} };
        }
    }

    return;
}

sub _update_node_table ( $self, $nodes ) {
    $self->{_nodes} = $nodes;

    # remove self from node table
    delete $nodes->{ $self->{id} };

    my $changed;

    for my $node ( values $nodes->%* ) {
        my $node_id = $node->{id};

        my $node_is_required = $node->{is_required} = $self->{_has_requires} && exists $self->{requires}->{ $node->{type} };

        # node already connected
        if ( my $connected_node = $self->{_connected_nodes}->{$node_id} ) {

            # node status was changed
            if ( $connected_node->{is_online} != $node->{is_online} ) {
                $connected_node->{is_online} = $node->{is_online};

                $changed = 1 if $node_is_required;

                # node connection status changed to online
                if ( $node->{is_online} ) {

                    # resume events listener
                    $connected_node->{h}->resume_events;

                    # add node to online nodes
                    unshift $self->{_online_nodes}->{ $node->{type} }->@*, $connected_node->{h};
                }

                # node connection status changed to offline
                else {

                    # suspend events listener
                    $connected_node->{h}->suspend_events;

                    # remove node from online nodes
                    $self->_remove_online_node( $node_id, $connected_node->{type} );
                }
            }
        }

        # node is not connected and is required
        elsif ($node_is_required) {
            $self->_connect_node($node_id);
        }
    }

    $self->_check_status if $changed;

    return;
}

sub _remove_online_node ( $self, $node_id, $node_type ) {
    my $online_nodes = $self->{_online_nodes}->{$node_type};

    # remove node from online nodes
    for ( my $i = 0; $i <= $online_nodes->$#*; $i++ ) {
        if ( $online_nodes->[$i]->{node_id} eq $node_id ) {
            splice $online_nodes->@*, $i, 1;

            last;
        }
    }

    return;
}

sub _check_status ($self) {
    my $is_online = 1;

    # calculate node online status
    if ( $self->{_has_requires} ) {
        for my $type ( keys $self->{requires}->%* ) {
            next if $type eq '*';

            # required node type is offline
            if ( !exists $self->{_online_nodes}->{$type} || !$self->{_online_nodes}->{$type}->@* ) {
                $is_online = 0;
            }

            # node type is online and has wait node callbacks
            elsif ( exists $self->{_wait_node_cb}->{$type} ) {

                # call pending callbacks
                for my $cb ( values delete( $self->{_wait_node_cb}->{$type} )->%* ) { $cb->() }
            }
        }

    }

    # update node status
    if ( $self->{is_online} != $is_online ) {
        $self->{is_online} = $is_online;

        # update status on server
        if ( defined $self->{server} && $self->{server_is_online} ) {
            if ( $self->{_server_is_remote} ) { $self->{_remote_server_h}->rpc_call( 'update_status', $is_online ) }
            else                              { $self->{server}->update_node_status( $self->{id}, $is_online ) }
        }

        # call "on_status_change" callback
        $self->{on_status_change}->( $self, $is_online ) if $self->{on_status_change};

        # status was changed to "online" and has "wait_online" callbacks
        if ( $is_online && $self->{_wait_online_cb} ) {

            # call pending "wait_for_online" callbacks
            for my $cb ( values delete( $self->{_wait_online_cb} )->%* ) { $cb->() }
        }
    }

    return;
}

sub wait_online ( $self, $timeout = undef ) {
    return 1 if $self->{is_online};

    my $rouse_cb = Coro::rouse_cb;

    my $id = refaddr $rouse_cb;

    $self->{_wait_online_cb}->{$id} = $rouse_cb;

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

    Coro::rouse_wait $rouse_cb;

    return $self->{is_online};
}

sub online_nodes ( $self, $type ) {
    return 0 if !$self->{_online_nodes}->{$type};

    return scalar $self->{_online_nodes}->{$type}->@*;
}

sub wait_node ( $self, $type, $timeout = undef ) {

    # only required nodes can be monitored
    return if !$self->{_has_requires} || !exists $self->{requires}->{$type};

    my $online_nodes = $self->online_nodes($type);

    return $online_nodes if $online_nodes;

    my $rouse_cb = Coro::rouse_cb;

    my $id = refaddr $rouse_cb;

    $self->{_wait_node_cb}->{$type}->{$id} = $rouse_cb;

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

    Coro::rouse_wait $rouse_cb;

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
    my $rouse_cb = Coro::rouse_cb;

    my $cv = AE::cv sub { $rouse_cb->() };

    $cv->begin;

    weaken $self;

    my $cpus_num = P->sys->cpus_num;

    my $server = do {
        if ( ref $self->{server} eq 'Pcore::Node::Server' ) {
            $self->{server}->{connect};
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

    $cv->end;

    Coro::rouse_wait $rouse_cb;

    return res 200;
}

# TODO repaat to other node if node returns 1013 Try Again Later
sub rpc_call ( $self, $type, $method, @args ) {
    my $h = shift $self->{_online_nodes}->{$type}->@*;

    if ( !defined $h ) {
        my $res = res [ 404, qq[Node type "$type" is not available] ];

        my $cb = is_plain_coderef $args[-1] || ( is_blessed_ref $args[-1] && $args[-1]->can('IS_CALLBACK') ) ? pop @args : undef;

        return $cb ? $cb->($res) : $res;
    }

    push $self->{_online_nodes}->{$type}->@*, $h;

    return $h->rpc_call( $method, @args );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 535                  | ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            |
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
