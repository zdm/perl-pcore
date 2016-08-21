package Pcore::Util::PM::RPC;

use Pcore -class, -const, -export => { CONST => [qw[$RPC_MSG_TERM]] };
use Pcore::Util::PM::RPC::Proc;
use Config;
use Pcore::Util::Scalar qw[weaken];
use Pcore::Util::UUID qw[uuid_str];
use Pcore::Util::PM::RPC::Request;

has class => ( is => 'ro', isa => Str, required => 1 );    # RPC object class name
has name  => ( is => 'ro', isa => Str, required => 1 );    # RPC process name for process manager
has buildargs => ( is => 'ro', isa => Maybe [HashRef] );              # RPC object constructor arguments
has on_call => ( is => 'ro', isa => Maybe [ HashRef [CodeRef] ] );    # CodeRef->($cb, @args), $cb can be undef, if is not required on remote side

has _workers     => ( is => 'ro', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _workers_idx => ( is => 'ro', isa => HashRef,  default => sub { {} }, init_arg => undef );
has _queue       => ( is => 'ro', isa => HashRef,  default => sub { {} }, init_arg => undef );
has _term => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

const our $RPC_MSG_TERM => 1;

around new => sub ( $orig, $self, $class, @args ) {
    my %args = (
        buildargs => undef,                                           # Maybe[HashRef], RPC object constructor arguments
        on_call   => undef,                                           # CodeRef($cb, $method, $data)
        workers   => undef,                                           # FALSE - max. CPUs, -n - CPUs - n || 1
        name      => $class,
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
        name      => $self->name,
        buildargs => $self->buildargs,
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

sub _on_data ( $self, $data ) {
    $ENV->add_deps( $data->{deps} ) if $ENV->{SCAN_DEPS} && $data->{deps};

    # RPC method call
    if ( $data->{method} ) {
        $self->_on_method_call( $data->{pid}, $data->{cid}, $data->{method}, $data->{args} );
    }

    # RPC callback
    else {
        if ( my $cb = delete $self->_queue->{ $data->{cid} } ) {
            $cb->( $data->{args} ? $data->{args}->@* : () );
        }
    }

    return;
}

sub _on_method_call ( $self, $worker_pid, $cid, $method, $args ) {
    if ( !$self->{on_call} || !exists $self->{on_call}->{$method} ) {
        die qq[RPC worker trying to call method "$method"];
    }
    else {
        my $cb;

        if ( defined $cid ) {
            $cb = sub ($args = undef) {
                my $cbor = P->data->to_cbor(
                    {   cid  => $cid,
                        args => $args,
                    }
                );

                my $worker = $self->{_workers_idx}->{$worker_pid};

                $worker->in->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

                return;
            };
        }

        my $req = bless {
            cid        => $cid,
            cb         => $cb,
            worker_pid => $worker_pid,
          },
          'Pcore::Util::PM::RPC::Request';

        $self->{on_call}->{$method}->( $req, $args ? $args->@* : () );
    }

    return;
}

# $method = Str, @args, $cb = Maybe[CodeRef]
sub rpc_call ( $self, $method, @ ) {

    # stop creating new calls in the term state
    return if $self->{_term};

    my ( $cid, $cb, $args );

    if ( @_ > 2 ) {
        if ( ref $_[-1] eq 'CODE' ) {
            $cb = $_[-1];

            $args = [ splice @_, 2, -1 ];

            $cid = uuid_str();

            $self->_queue->{$cid} = $cb;
        }
        else {
            $args = [ splice @_, 2 ];
        }
    }

    # select worker, round-robin
    my $worker = shift $self->_workers->@*;

    push $self->_workers->@*, $worker;

    # prepare CBOR data
    my $cbor = P->data->to_cbor(
        {   cid    => $cid,
            method => $method,
            args   => $args,
        }
    );

    $worker->in->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

    return;
}

# $method = Str, @args
sub rpc_call_all ( $self, $method, @ ) {

    # stop creating new calls in the term state
    return if $self->{_term};

    my $cbor = P->data->to_cbor(
        {   method => $method,
            args   => @_ > 2 ? [ splice @_, 2 ] : undef,
        }
    );

    for my $worker ( $self->_workers->@* ) {
        $worker->in->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );
    }

    return;
}

sub rpc_term ( $self, $cb = undef ) {

    # stop creating new messages in the term state
    return if $self->{_term};

    $self->{_term} = 1;

    my $cv = AE::cv sub {
        $cb->() if $cb;

        return 1;
    };

    my $cbor = P->data->to_cbor( { msg => $RPC_MSG_TERM } );

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
## |    3 | 167                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 117                  | ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            |
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
