package Pcore::Util::PM::RPC;

use Pcore -class;
use Pcore::Util::PM::RPC::Proc;
use Config;
use Pcore::Util::Scalar qw[weaken];

has class => ( is => 'ro', isa => Str, required => 1 );
has new_args => ( is => 'ro', isa => Maybe [HashRef], init_arg => undef );

has _workers => ( is => 'ro', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _call_id => ( is => 'ro', default => 0, init_arg => undef );
has _queue => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has _scan_deps => ( is => 'lazy', isa => Bool, init_arg => undef );

around new => sub ( $orig, $self, $class, @args ) {
    my %args = (
        new_args => undef,
        workers  => undef,
        splice @_, 3,
    );

    # create RPC object
    my $rpc = $self->$orig(
        {   class    => $class,
            new_args => $args{new_args},
        }
    );

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
        new_args  => $self->new_args,
        scan_deps => $self->_scan_deps,

        # on_data   => sub ($data) {
        #     $self->_on_data(@_) if $self;
        #
        #     return;
        # },
        on_ready => sub ($rpc_proc) {
            push $self->{_workers}->@*, $rpc_proc;

            # install listener
            $rpc_proc->out->on_read(
                sub ($h) {
                    $self->_on_read($h);

                    return;
                }
            );

            $cv->end;

            return;
        },
    );

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
    $self->_store_deps( $data->[0]->[0] ) if $data->[0]->[0] && $self->_scan_deps;

    if ( my $cb = delete $self->_queue->{ $data->[0]->[1] } ) {
        $cb->( $data->[1] );
    }

    return;
}

sub _store_deps ( $self, $deps ) {
    my $old_deps = -f "$ENV->{DATA_DIR}.pardeps.cbor" ? P->cfg->load("$ENV->{DATA_DIR}.pardeps.cbor") : {};

    my $new_deps;

    for my $mod ( keys $deps->%* ) {
        if ( !exists $old_deps->{ $ENV->{SCRIPT_NAME} }->{ $Config{archname} }->{$mod} ) {
            $new_deps = 1;

            say 'new deps found: ' . $mod;

            $old_deps->{ $ENV->{SCRIPT_NAME} }->{ $Config{archname} }->{$mod} = $deps->{$mod};
        }
    }

    P->cfg->store( "$ENV->{DATA_DIR}.pardeps.cbor", $old_deps ) if $new_deps;

    return;
}

sub call ( $self, $method, $data = undef, $cb = undef ) {
    my $call_id = ++$self->{call_id};

    $self->_queue->{$call_id} = $cb if $cb;

    # select worker, round-robin
    my $worker = shift $self->_workers->@*;

    push $self->_workers->@*, $worker;

    my $cbor = P->data->to_cbor( [ $call_id, $method, $data ] );

    $worker->in->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 131                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
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
