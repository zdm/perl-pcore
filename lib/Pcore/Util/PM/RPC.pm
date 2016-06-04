package Pcore::Util::PM::RPC;

use Pcore -class, -const, -export => { CONST => [qw[$RPC_MSG_TERM]] };
use Pcore::Util::PM::RPC::Proc;
use Config;
use Pcore::Util::Scalar qw[weaken];

has class => ( is => 'ro', isa => Str, required => 1 );    # RPC object class name
has buildargs => ( is => 'ro', isa => Maybe [HashRef] );   # RPC object constructor arguments
has on_call   => ( is => 'ro', isa => Maybe [CodeRef] );   # CodeRef($cb, $method, $data), $cb can be undef, if is not required on remote side

has _workers     => ( is => 'ro', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _workers_idx => ( is => 'ro', isa => HashRef,  default => sub { {} }, init_arg => undef );
has _call_id => ( is => 'ro', default => 0, init_arg => undef );
has _queue => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has _scan_deps => ( is => 'lazy', isa => Bool, init_arg => undef );
has _term => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

const our $RPC_MSG_TERM => 1;

around new => sub ( $orig, $self, $class, @args ) {
    my %args = (
        buildargs => undef,                                # Maybe[HashRef], RPC object constructor arguments
        on_call   => undef,                                # CodeRef($cb, $method, $data)
        workers   => undef,                                # FALSE - max. CPUs, -n - CPUs - n || 1
        splice( @_, 3 ),
        class => $class,
    );

    # create RPC object
    my $rpc = $self->$orig( \%args );

    # defined number of the workers
    if ( !$args{workers} ) {
        $args{workers} = P->sys->cpus_num;
    }
    elsif ( $args{workers} < 0 ) {
        $args{workers} = P->sys->cpus_num + $args{workers};

        $args{workers} = 1 if $args{workers} <= 0;
    }

    my $blocking_cv = AE::cv;

    $blocking_cv->begin;

    # create workers
    for ( 1 .. $args{workers} ) {
        $rpc->_create_worker($blocking_cv);
    }

    $blocking_cv->end;

    $blocking_cv->recv;

    return $rpc;
};

sub _create_worker ( $self, $cv ) {
    weaken $self;

    $cv->begin;

    Pcore::Util::PM::RPC::Proc->new(
        class     => $self->class,
        buildargs => $self->buildargs,
        scan_deps => $self->_scan_deps,
        on_ready  => sub ($worker) {
            push $self->{_workers}->@*, $worker;

            $self->{_workers_idx}->{ $worker->pid } = $worker;

            # install on_error
            $worker->in->on_error(
                sub ( $h, $fatal, $msg ) {
                    $self->_on_worker_finish($worker);

                    return;
                }
            );

            $worker->out->on_error(
                sub ( $h, $fatal, $msg ) {
                    $self->_on_worker_finish($worker);

                    return;
                }
            );

            # install listener
            $worker->out->on_read(
                sub ($h) {
                    $self->_on_read($h);

                    return;
                }
            );

            $cv->end;

            return;
        },
        on_finish => sub ($worker) {
            $self->_on_worker_finish($worker);

            return;
        }
    );

    return;
}

sub _on_worker_finish ( $self, $worker ) {
    if ( delete $self->{_workers_idx}->{ $worker->pid } ) {
        for ( my $i = 0; $i <= $self->{_workers}->$#*; $i++ ) {
            if ( $self->{_workers}->[$i] eq $worker ) {
                splice $self->{_workers}->@*, $i, 1, ();

                last;
            }
        }
    }

    return;
}

sub _on_read ( $self, $h ) {
    $h->unshift_read(
        chunk => 4,
        sub ( $h, $len ) {
            $h->unshift_read(
                chunk => unpack( 'L>', $len ),
                sub ( $h, $data ) {
                    $self->_on_data( P->data->from_cbor($data) );

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub _build__scan_deps ($self) {
    return exists $INC{'Pcore/Devel/ScanDeps.pm'} ? 1 : 0;
}

sub _on_data ( $self, $data ) {
    return if $self->{_term};

    Pcore::Devel::ScanDeps->add_deps( $data->[0]->{deps} ) if $data->[0]->{deps} && $self->_scan_deps;

    if ( $data->[0]->{method} ) {
        $self->_on_call( $data->[0]->{pid}, $data->[0]->{call_id}, $data->[0]->{method}, $data->[1] );
    }
    else {
        if ( my $cb = delete $self->_queue->{ $data->[0]->{call_id} } ) {
            $cb->( $data->[1] );
        }
    }

    return;
}

sub _on_call ( $self, $worker_pid, $call_id, $method, $data ) {
    if ( !$self->on_call ) {
        die qq[RPC worker trying to call method "$method"];
    }
    else {
        my $cb = !defined $call_id ? undef : sub ($data = undef) {
            my $cbor = P->data->to_cbor( [ { call_id => $call_id, }, $data ] );

            my $worker = $self->{_workers_idx}->{$worker_pid};

            $worker->in->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

            return;
        };

        $self->on_call->( $cb, $method, $data );
    }

    return;
}

sub rpc_call ( $self, $method, $data = undef, $cb = undef ) {
    return if $self->{_term};

    my $call_id;

    if ($cb) {
        $call_id = ++$self->{call_id};

        $self->_queue->{$call_id} = $cb;
    }

    # select worker, round-robin
    my $worker = shift $self->_workers->@*;

    push $self->_workers->@*, $worker;

    # prepare CBOR data
    my $cbor = P->data->to_cbor( [ { call_id => $call_id, method => $method }, $data ] );

    $worker->in->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

    return;
}

sub rpc_call_all ( $self, $method, $data = undef ) {
    return if $self->{_term};

    my $cbor = P->data->to_cbor( [ { call_id => undef, method => $method }, $data ] );

    for my $worker ( $self->_workers->@* ) {
        $worker->in->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );
    }

    return;
}

sub rpc_term ( $self, $cb = undef ) {
    return if $self->{_term};

    $self->{_term} = 1;

    my $cv = AE::cv sub {
        $cb->() if $cb;

        return 1;
    };

    my $cbor = P->data->to_cbor( [ { msg => $RPC_MSG_TERM } ] );

    $cv->begin;

    # send TERM message to all workers
    for my $worker ( $self->_workers->@* ) {
        $cv->begin;

        $worker->in->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

        $worker->on_finish(
            sub ($worker) {
                $self->_on_worker_finish($worker);

                $cv->end;

                return;
            }
        );
    }

    $cv->end;

    return defined wantarray ? $cv->recv : ();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 168                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 115                  | ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::RPC

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
