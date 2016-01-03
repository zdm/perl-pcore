package Pcore::Util::PM::RPC;

use Pcore -class;
use Config;
use Pcore::Util::PM::RPC::Proc;

has class   => ( is => 'ro', isa => Str,         required => 1 );
has args    => ( is => 'ro', isa => HashRef,     required => 1 );
has workers => ( is => 'ro', isa => PositiveInt, required => 1 );

has on_ready => ( is => 'ro', isa => Maybe [CodeRef] );
has on_exit  => ( is => 'ro', isa => Maybe [CodeRef] );

has _workers => ( is => 'lazy', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _call_id => ( is => 'ro', default => 0, init_arg => undef );
has _queue => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );
has _scan_deps => ( is => 'lazy', isa => Bool, init_arg => undef );

sub BUILDARGS ( $self, $args ) {
    $args->{args} //= {};

    $args->{workers} ||= P->sys->cpus_num;

    return $args;
}

sub BUILD ( $self, $args ) {
    my $cv = AE::cv {
        my $listen_cb = sub ($data) {
            $self->_store_deps( $data->[0] ) if $data->[0] && $self->_scan_deps;

            if ( my $cb = delete $self->_queue->{ $data->[1] } ) {
                $cb->( $data->[2] );
            }

            return;
        };

        # run listeners
        for ( $self->_workers->@* ) {
            $_->start_listen($listen_cb);
        }

        $self->on_ready->($self) if $self->on_ready;

        return;
    };

    for ( 1 .. $self->workers ) {
        $self->_create_worker($cv);
    }

    return;
}

sub _create_worker ( $self, $cv ) {
    $cv->begin;

    push $self->_workers->@*, Pcore::Util::PM::RPC::Proc->new(
        {   class     => $self->class,
            args      => $self->args,
            scan_deps => $self->_scan_deps,
            on_ready  => sub ($worker) {
                $cv->end;

                return;
            }
        }
    );

    return;
}

sub _build__scan_deps ($self) {
    return exists $INC{'Pcore/Devel/ScanDeps.pm'} ? 1 : 0;
}

sub call ( $self, $method, $data = undef, $cb = undef ) {
    my $call_id = ++$self->{call_id};

    $self->queue->{$call_id} = $cb if $cb;

    my $worker = shift $self->_workers->@*;

    push $self->_workers->@*, $worker;

    my $cbor = P->data->to_cbor( [ $call_id, $method, $data ] );

    $worker->out->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

    return;
}

sub _store_deps ( $self, $deps ) {
    my $old_deps = -f "$ENV->{DATA_DIR}.pardeps.cbor" ? P->cfg->load("$ENV->{DATA_DIR}.pardeps.cbor") : {};

    my $new_deps;

    for my $pkg ( keys $deps->%* ) {
        if ( !exists $old_deps->{ $ENV->{SCRIPT_NAME} }->{ $Config{archname} }->{$pkg} ) {
            $new_deps = 1;

            say 'new deps found: ' . $pkg;

            $old_deps->{ $ENV->{SCRIPT_NAME} }->{ $Config{archname} }->{$pkg} = $deps->{$pkg};
        }
    }

    P->cfg->store( "$ENV->{DATA_DIR}.pardeps.cbor", $old_deps ) if $new_deps;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 99                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
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
