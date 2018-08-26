package Pcore::Core::Event::Listener;

use Pcore -role;
use Pcore::Util::Scalar qw[weaken is_plain_arrayref];

requires qw[_build_id forward_event];

has broker => ( required => 1 );    # InstanceOf ['Pcore::Core::Event']
has uri    => ( required => 1 );
has is_suspended => 0;

has id       => ( init_arg => undef );
has bindings => ( sub { {} }, init_arg => undef );

sub BUILD ( $self, $args ) { }

around BUILD => sub ( $orig, $self, $args ) {
    $self->$orig($args);

    $self->{id} = $self->_build_id;

    return;
};

sub DESTROY ( $self ) {
    $self->destroy if ${^GLOBAL_PHASE} ne 'DESTRUCT';

    return;
}

sub suspend ($self) {
    $self->{is_suspended} = 1;

    return;
}

sub resume ($self) {
    $self->{is_suspended} = 0;

    return;
}

sub bind ( $self, $bindings ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    return if !defined $bindings;

    my $id              = $self->{id};
    my $my_bindings     = $self->{bindings};
    my $broker_bindings = $self->{broker}->{_bindings};

    for my $binding ( is_plain_arrayref $bindings ? $bindings->@* : $bindings ) {
        if ( !exists $my_bindings->{$binding} ) {
            $my_bindings->{$binding} = 1;

            $broker_bindings->{$binding}->{$id} = $self;

            weaken $broker_bindings->{$binding}->{$id};
        }
    }

    return;
}

sub unbind ( $self, $bindings ) {
    return if !defined $bindings;

    my $id              = $self->{id};
    my $my_bindings     = $self->{bindings};
    my $broker_bindings = $self->{broker}->{_bindings};

    for my $binding ( is_plain_arrayref $bindings ? $bindings->@* : $bindings ) {
        delete $broker_bindings->{$binding}->{$id} if defined delete $my_bindings->{$binding};
    }

    return;
}

sub unbind_all ( $self ) {
    my $id              = $self->{id};
    my $broker_bindings = $self->{broker}->{_bindings};

    for my $binding ( keys $self->{bindings}->%* ) { delete $broker_bindings->{$binding}->{$id} }

    $self->{bindings}->%* = ();

    return;
}

sub destroy ($self) {
    my $broker          = $self->{broker};
    my $id              = $self->{id};
    my $broker_bindings = $broker->{_bindings};

    delete $broker->{_listeners}->{$id};

    for my $binding ( keys $self->{bindings}->%* ) { delete $broker_bindings->{$binding}->{$id} }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Event::Listener

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
