package Pcore::Util::PM::RPC;

use Pcore -class;
use Config;
use Pcore::Util::PM::RPC::Proc;

has class   => ( is => 'ro', isa => Str,         required => 1 );
has args    => ( is => 'ro', isa => HashRef,     required => 1 );
has workers => ( is => 'ro', isa => PositiveInt, required => 1 );    # -1 - CPU's num - x
has std     => ( is => 'ro', isa => Bool,        default  => 0 );
has console => ( is => 'ro', isa => Bool,        default  => 1 );
has on_ready => ( is => 'ro', isa => Maybe [CodeRef] );

has _workers => ( is => 'lazy', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _call_id => ( is => 'ro', default => 0, init_arg => undef );
has _queue => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );
has _scan_deps => ( is => 'lazy', isa => Bool, init_arg => undef );

sub BUILDARGS ( $self, $args ) {
    $args->{args} //= {};

    if ( !$args->{workers} ) {
        $args->{workers} = P->sys->cpus_num;
    }
    elsif ( $args->{workers} < 0 ) {
        $args->{workers} = P->sys->cpus_num + $args->{workers};

        $args->{workers} = 1 if $args->{workers} <= 0;
    }

    return $args;
}

sub BUILD ( $self, $args ) {
    P->scalar->weaken($self);

    my $on_ready = AE::cv {
        $self->on_ready->($self) if $self->on_ready;

        return;
    };

    for ( 1 .. $self->workers ) {
        $on_ready->begin;

        push $self->_workers->@*, Pcore::Util::PM::RPC::Proc->new(
            {   std       => $self->std,
                console   => $self->console,
                blocking  => 0,
                class     => $self->class,
                args      => $self->args,
                scan_deps => $self->_scan_deps,
                on_ready  => sub ($worker) {
                    $on_ready->end;

                    return;
                },
                on_exit => sub ( $worker, $status ) {
                    return;
                },
                on_data => sub ($data) {
                    $self->_on_data(@_) if $self;

                    return;
                },
            }
        );
    }

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
## │    3 │ 92                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
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
