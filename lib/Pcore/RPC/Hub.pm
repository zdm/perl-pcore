package Pcore::RPC::Hub;

use Pcore -class, -result;
use Pcore::Util::Scalar qw[weaken is_plain_coderef is_blessed_ref];
use Pcore::RPC::Proc;
use Pcore::WebSocket;

has id    => ( is => 'ro', isa => Maybe [Str] );
has class => ( is => 'ro', isa => Maybe [Str] );

has proc       => ( is => 'ro', isa => HashRef,  init_arg => undef );    # child RPC processes
has conn       => ( is => 'ro', isa => HashRef,  init_arg => undef );
has conn_class => ( is => 'ro', isa => ArrayRef, init_arg => undef );

has _on_rpc_started => ( is => 'ro', init_arg => undef );                # event listener

sub BUILD ( $self, $args ) {
    weaken $self;

    $self->{_on_rpc_started} = P->listen_events(
        'RPC.STARTED',
        sub ($ev) {
            for my $rpc ( $ev->{data}->@* ) {

                # do not connect to the already connected servers
                next if exists $self->{conn}->{ $rpc->{id} };

                # do not connect to the RPC servers with the same class
                next if defined $self->{class} && $self->{class} eq $rpc->{class};

                # do not connect to myself
                next if defined $self->{id} && $self->{id} eq $rpc->{id};

                $self->_connect_rpc($rpc);
            }

            return;
        }
    );

    return;
}

sub run_rpc ( $self, $args, $cb ) {
    my $cv = AE::cv sub { $cb->() };

    $cv->begin;

    weaken $self;

    for my $rpc ( $args->@* ) {

        # resolve number of the workers
        if ( !$rpc->{workers} ) {
            $rpc->{workers} = P->sys->cpus_num;
        }
        elsif ( $rpc->{workers} < 0 ) {
            $rpc->{workers} = P->sys->cpus_num - $rpc->{workers};

            $rpc->{workers} = 1 if $rpc->{workers} <= 0;
        }

        # run workers
        for ( 1 .. $rpc->{workers} ) {
            $cv->begin;

            Pcore::RPC::Proc->new(
                listen    => $rpc->{listen},
                token     => $rpc->{token},
                class     => $rpc->{class},
                buildargs => $rpc->{buildargs},
                on_ready  => sub ($proc) {
                    $self->{proc}->{ $proc->{id} } = $proc;

                    $self->_connect_rpc(
                        {   id     => $proc->{id},
                            class  => $proc->{class},
                            listen => $proc->{listen},
                            token  => $rpc->{token},
                        },
                        sub {

                            # send updated routes to all connected RPC servers
                            P->fire_event( 'RPC.STARTED', [ values $self->{conn}->%* ] );

                            $cv->end;

                            return;
                        }
                    );

                    return;
                },
                on_finish => sub ($proc) {
                    $self->_on_proc_finish($proc) if defined $self;

                    return;
                }
            );
        }
    }

    $cv->end;

    return;
}

sub _connect_rpc ( $self, $rpc, $cb = undef ) {
    weaken $self;

    $self->{conn}->{ $rpc->{id} } = $rpc;

    Pcore::WebSocket->connect_ws(
        "ws://$rpc->{listen}/",
        protocol       => 'pcore',
        before_connect => {
            token          => $rpc->{token},
            listen_events  => $rpc->{listen_events},
            forward_events => [ 'RPC.STARTED', defined $rpc->{forward_events} ? $rpc->{forward_events}->@* : () ],
        },
        on_listen_event => sub ( $ws, $mask ) {    # RPC server can listen client event
            return 1;
        },
        on_fire_event => sub ( $ws, $key ) {       # RPC server can fire client event
            return 1;
        },
        on_connect_error => sub ($status) {
            die "$status";
        },
        on_connect => sub ( $ws, $headers ) {

            # store established connection
            push $self->{conn_class}->{ $rpc->{class} }->@*, $ws;

            $cb->() if defined $cb;

            return;
        },
        on_disconnect => sub ( $ws, $status ) {
            $self->_on_rpc_disconnect( $ws, $status ) if defined $self;

            return;
        }
    );

    return;
}

# TODO
sub _on_proc_finish ( $self, $proc ) {

    # if ($weaken_rpc) {
    #     for ( my $i = 0; $i <= $weaken_rpc->{workers}->$#*; $i++ ) {
    #         if ( $weaken_rpc->{workers}->[$i] eq $proc ) {
    #             splice $weaken_rpc->{workers}->@*, $i, 1, ();
    #
    #             last;
    #         }
    #     }
    # }

    return;
}

# TODO
sub _on_rpc_disconnect ( $self, $ws, $status ) {

    # remove destroyed connection from cache
    # for ( my $i = 0; $i <= $self_weak->{connections}->$#*; $i++ ) {
    #     if ( $self_weak->{connections}->[$i] eq $ws ) {
    #         splice $self_weak->{connections}->@*, $i, 1, ();
    #
    #         last;
    #     }
    # }

    return;
}

sub rpc_call ( $self, $class, $method, @ ) {
    my $ws = shift $self->{conn_class}->{$class}->@*;

    if ( defined $ws ) {
        push $self->{conn_class}->{$class}->@*, $ws;

        $ws->rpc_call( @_[ 2 .. $#_ ] );
    }
    elsif ( is_plain_coderef $_[-1] || ( is_blessed_ref $_[-1] && $_[-1]->can('IS_CALLBACK') ) ) {
        $_[-1]->( result [ 404, 'Method is not available' ] );
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::RPC::Hub

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
