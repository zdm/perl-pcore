package Pcore::Core::EV::Queue;

use Pcore -class;
use Pcore::Core::EV::Object;

has _queue => ( is => 'lazy', isa => HashRef, init_arg => undef );
has _id => ( is => 'rwp', isa => Int, default => 0, init_arg => undef );

sub _build__queue {
    my $self = shift;

    return {};
}

sub _inc_id {
    my $self = shift;

    $self->_set__id( $self->_id + 1 );

    return;
}

sub register {
    my $self     = shift;
    my $ev       = shift;
    my $code_ref = shift;
    my %args     = (
        disposable => 0,    # one-time event
        extrusive  => 0,    # replace all previous events in queue
        args       => [],
        @_,
    );

    die 'Event queue must be defined' unless $self->has_queue($ev);

    delete $self->_queue->{$ev} if $args{extrusive};

    my $caller = caller;
    $self->_inc_id;
    my $id = $self->_id;

    $self->_queue->{$ev}->{$id} = {
        id       => \$id,
        caller   => $caller,
        code_ref => $code_ref,
        args     => \%args,
    };

    P->class->set_subname( "${caller}::${ev}_event_handler" => $self->_queue->{$ev}->{$id}->{code_ref} );
    P->scalar->weaken( $self->_queue->{$ev}->{$id}->{id} ) if defined wantarray;
    return \$id;
}

sub throw {
    my $self = shift;
    my $ev   = shift;

    die 'Event queue must be defined' unless $self->has_queue($ev);

    my $obj = Pcore::Core::EV::Object->new( { class => $ev } );

    if ( $self->_queue->{$ev} ) {
        for my $id ( sort { $a <=> $b } keys $self->_queue->{$ev}->%* ) {
            unless ( $self->_queue->{$ev}->{$id}->{id} ) {
                delete $self->_queue->{$ev}->{$id};

                next;
            }
            $self->_queue->{$ev}->{$id}->{code_ref}->( $obj, $self->_queue->{$ev}->{$id}->{args}->{args}->@* );

            delete $self->_queue->{$ev}->{$id} if $self->_queue->{$ev}->{$id}->{args}->{disposable};    # delete disposable event

            delete $self->_queue->{$ev}->{$id} if $obj->_remove;                                        # delete self-removed event

            last if $obj->_stop_propagate;                                                              # stop propagate on demand from event
        }
    }
    return;
}

sub has_queue {
    my $self = shift;
    my $ev   = shift;

    if ( $ev =~ /\A([^#]+)#.+\z/sm ) {
        return $1;
    }
    else {
        return;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 63                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::EV::Queue

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
