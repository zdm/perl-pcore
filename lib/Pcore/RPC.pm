package Pcore::RPC;

use Pcore -class;
use Pcore::Util::Scalar qw[blessed];
use Pcore::RPC::Proc;
use Pcore::WebSocket;

has workers     => ( is => 'ro', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has connections => ( is => 'ro', isa => ArrayRef, default => sub { [] }, init_arg => undef );

sub TO_DATA ( $self, ) {
    return $self->get_listen;
}

sub run_rpc ( $self, $class, @ ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my %args = (
        workers   => undef,    # FALSE - max. CPUs, -n - CPUs - n || 1
        buildargs => undef,    # Maybe[HashRef], RPC object constructor arguments
        on_ready  => undef,    # Maybe[CodeRef]
        @_[ 2 .. $#_ ],
    );

    # define number of the workers
    if ( !$args{workers} ) {
        $args{workers} = P->sys->cpus_num;
    }
    elsif ( $args{workers} < 0 ) {
        $args{workers} = P->sys->cpus_num - $args{workers};

        $args{workers} = 1 if $args{workers} <= 0;
    }

    my $rpc = bless {}, $self;

    my $cv = AE::cv sub {
        $args{on_ready}->($rpc) if $args{on_ready};

        $blocking_cv->($rpc) if $blocking_cv;

        return;
    };

    $cv->begin;

    # create workers
    for ( 1 .. $args{workers} ) {
        $cv->begin;

        Pcore::RPC::Proc->new(
            class     => $class,
            buildargs => $args{buildargs},
            on_ready  => sub ($proc) {
                push $rpc->{workers}->@*, $proc;

                $cv->end;

                return;
            },
            on_finish => sub ($proc) {
                for ( my $i = 0; $i <= $rpc->{workers}->$#*; $i++ ) {
                    if ( $rpc->{workers}->[$i] eq $proc ) {
                        splice $rpc->{workers}->@*, $i, 1, ();

                        last;
                    }
                }

                return;
            }
        );
    }

    $cv->end;

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub connect_rpc ( $self, % ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my %args = (
        addr       => undef,
        on_connect => undef,    # called for each handle individually
        on_ready   => undef,
        @_[ 1 .. $#_ ],
    );

    $self = bless {}, $self if !blessed $self;

    if ( !$args{addr} ) {
        $args{addr} = $self->get_listen;
    }
    else {
        $args{addr} = [ $args{addr} ] if ref $args{addr} ne 'ARRAY';
    }

    die q[No addresses specified] if !$args{addr}->@*;

    my $cv = AE::cv sub {
        $args{on_ready}->($self) if $args{on_ready};

        $blocking_cv->($self) if $blocking_cv;

        return;
    };

    $cv->begin;

    for my $addr ( $args{addr}->@* ) {
        $cv->begin;

        Pcore::WebSocket->connect_ws(
            pcore    => "ws://$addr/",
            on_error => sub ($res) {
                die $res;
            },
            on_connect => sub ( $ws, $headers ) {
                push $self->{connections}->@*, $ws;

                $args{on_connect}->($ws) if $args{on_connect};

                $cv->end;

                return;
            },
            on_disconnect => sub ( $ws, $status ) {
                for ( my $i = 0; $i <= $self->{connections}->$#*; $i++ ) {
                    if ( $self->{connections}->[$i] eq $ws ) {
                        splice $self->{connections}->@*, $i, 1, ();

                        last;
                    }
                }

                return;
            }
        );
    }

    $cv->end;

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub get_listen ($self) {
    return [ map { $_->{listen} } $self->{workers}->@* ];
}

sub rpc_call ( $self, $method, @ ) {
    my $ws = shift $self->{connections}->@*;

    push $self->{connections}->@*, $ws;

    $ws->rpc_call( @_[ 1 .. $#_ ] );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 62, 129              | ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::RPC

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
