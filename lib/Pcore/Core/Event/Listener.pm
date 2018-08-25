package Pcore::Core::Event::Listener;

use Pcore -role;
use Pcore::Util::Scalar qw[weaken is_plain_arrayref];

requires qw[_build_id forward_event];

has broker => ( required => 1 );    # InstanceOf ['Pcore::Core::Event']
has uri    => ( required => 1 );
has is_suspended => 0;

has id     => ( init_arg => undef );
has _masks => ( sub { {} }, init_arg => undef );

sub BUILD ( $self, $args ) { }

around BUILD => sub ( $orig, $self, $args ) {
    $self->$orig($args);

    $self->{id} = $self->_build_id;

    return;
};

sub DESTROY ( $self ) {
    $self->_remove if ${^GLOBAL_PHASE} ne 'DESTRUCT';

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

sub add_masks ( $self, $masks ) {
    my $id             = $self->{id};
    my $listener_masks = $self->{_masks};
    my $mask_listener  = $self->{broker}->{_mask_listener};

    for my $mask ( is_plain_arrayref $masks ? $masks->@* : $masks ) {
        if ( !exists $listener_masks->{$mask} ) {
            $listener_masks->{$mask} = 1;

            $mask_listener->{$mask}->{$id} = $self;

            weaken $mask_listener->{$mask}->{$id};
        }
    }

    return;
}

sub remove_masks ( $self, $masks ) {
    my $id             = $self->{id};
    my $listener_masks = $self->{_masks};
    my $mask_listener  = $self->{broker}->{_mask_listener};

    for my $mask ( is_plain_arrayref $masks ? $masks->@* : $masks ) {
        delete $mask_listener->{$mask}->{$id} if delete $listener_masks->{$mask};
    }

    return;
}

sub _remove ($self) {
    my $broker        = $self->{broker};
    my $id            = $self->{id};
    my $mask_listener = $broker->{_mask_listener};

    delete $broker->{_listeners}->{$id};

    for my $mask ( keys $self->{_masks}->%* ) { delete $mask_listener->{$mask}->{$id} }

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
