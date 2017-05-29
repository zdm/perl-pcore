package Pcore::Core::Event::Listener;

use Pcore -class;
use Pcore::Util::UUID qw[uuid_str];

has broker => ( is => 'ro', isa => InstanceOf ['Pcore::Core::Event'], required => 1 );
has events => ( is => 'ro', isa => ArrayRef, required => 1 );
has cb => ( is => 'ro', isa => CodeRef | Object, required => 1 );

has id => ( is => 'ro', isa => Str, init_arg => undef );

sub BUILD ( $self, $args ) {
    $self->{id} = uuid_str;

    return;
}

sub DEMOLISH ( $self, $global ) {
    $self->remove if !$global;

    return;
}

sub remove ($self) {
    for my $event ( $self->{events}->@* ) {
        delete $self->{broker}->{listeners}->{$event}->{ $self->{id} };

        if ( !$self->{broker}->{listeners}->{$event}->%* ) {
            delete $self->{broker}->{listeners}->{$event};

            delete $self->{broker}->{listeners_re}->{$event};
        }
    }

    # remove listener from senders events
    for my $event ( values $self->{broker}->{senders}->%* ) {
        delete $event->{ $self->{id} };
    }

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
