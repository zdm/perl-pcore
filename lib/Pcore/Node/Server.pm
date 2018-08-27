package Pcore::Node::Server;

use Pcore -class, -res;
use Pcore::Util::Scalar qw[weaken];
use Pcore::Util::UUID qw[uuid_v4_str];
use Pcore::HTTP::Server;
use Pcore::WebSocket::pcore;
use Clone qw[clone];

has token       => ();    # TODO take from listen
has listen      => ();
has compression => 0;

has id           => ( sub {uuid_v4_str}, init_arg => undef );
has connect      => ( init_arg                    => undef );    # connect url, including token
has _http_server => ( init_arg                    => undef );    # InstanceOf['Pcore::HTTP::Server']
has _nodes       => ( init_arg                    => undef );    # HashRef, node registry, node_id => {}
has _nodes_h     => ( init_arg                    => undef );    # HashRef, connected nodes handles, node_id => $handle

# TODO use uri method to insert token
sub BUILD ( $self, $args ) {
    weaken $self;

    $self->{token} //= P->uuid->uuid_v4_str;

    $self->{_http_server} = Pcore::HTTP::Server->new(
        listen     => $self->{listen},
        on_request => sub ($req) {
            if ( $req->is_websocket_connect_request ) {
                my $h = Pcore::WebSocket::pcore->accept(
                    $req,
                    compression   => $self->{compression},
                    on_disconnect => sub ($h) {
                        return if !defined $self;

                        $self->remove_node( $h->{node_id} );

                        return;
                    },
                    on_auth => sub ( $h, $token ) {
                        return if !defined $self;

                        ( $token, $h->{node_id}, $h->{node_data} ) = $token->@*;

                        if ( $self->{token} && $token ne $self->{token} ) {
                            $h->disconnect;

                            return;
                        }
                        else {
                            return res 200;
                        }
                    },
                    on_ready => sub ($h) {
                        $self->register_node( $h, $h->{node_id}, delete $h->{node_data}, 1 );

                        return;
                    },
                    on_rpc => sub ( $h, $req, $tx ) {
                        return if !defined $self;

                        if ( $tx->{method} eq 'update_status' ) {
                            $self->update_node_status( $h->{node_id}, $tx->{args}->[0] );
                        }

                        return;
                    },
                );
            }

            return;
        }
    )->run;

    my $listen = $self->{listen} = $self->{_http_server}->{listen};

    # TODO use uri method to insert token
    $self->{connect} = $listen->{scheme} ? "$listen->{scheme}://" : '//';
    $self->{connect} .= "$self->{token}@" if defined $self->{token};
    if ( my $host = "$listen->{host}" ) {
        $self->{connect} .= "$host:" . $listen->connect_port . '/';
    }
    else {
        $self->{connect} .= $listen->{path}->to_string;
    }

    return;
}

sub register_node ( $self, $node_h, $node_id, $node_data, $is_remote = 0 ) {
    $node_data->{is_online} //= 0;

    $self->{_nodes}->{$node_id} = $node_data;

    $self->{_nodes_h}->{$node_id} = {
        is_remote => $is_remote,
        h         => $node_h,
    };

    weaken $self->{_nodes_h}->{$node_id}->{h};

    $self->_on_update;

    return;
}

sub remove_node ( $self, $node_id ) {
    if ( exists $self->{_nodes}->{$node_id} ) {
        delete $self->{_nodes}->{$node_id};
        delete $self->{_nodes_h}->{$node_id};

        $self->_on_update;
    }

    return;
}

sub update_node_status ( $self, $node_id, $is_online ) {
    my $node = $self->{_nodes}->{$node_id};

    # node is unknown
    return if !defined $node;

    $is_online //= 0;

    # node status was changed
    if ( $node->{is_online} != $is_online ) {
        $node->{is_online} = $is_online;

        $self->_on_update;
    }

    return;
}

sub _on_update ($self) {
    for my $node ( values $self->{_nodes_h}->%* ) {
        next if !defined $node->{h};

        # remote node
        if ( $node->{is_remote} ) {
            $node->{h}->rpc_call( 'update_node_table', $self->{_nodes} );
        }

        # local node
        else {
            $node->{h}->_update_node_table( clone $self->{_nodes} );
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
## |    3 | 90                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Node::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
