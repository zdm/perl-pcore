package Pcore::Core::H::Role;

use Pcore qw[-role];

has h_disconnect_on => ( is => 'ro', isa => Maybe [ Enum [ 'PID_CHANGE', 'BEFORE_FORK', 'REQ_FINISH' ] ], default => undef );

# NOTE you need to define DESTROY or DEMOLISH method in h object to properly disconnect during global destruction.
# The order in which objects are destroyed during the global destruction before the program exits is unpredictable. This means that any objects contained by your object may already have been destroyed. You should check that a contained object is defined before calling a method on it
# http://perldoc.perl.org/perlobj.html#Destructors

sub h_disconnect {    # loopback, can be redefined in subclasses
    my $self = shift;

    return;
}

sub DEMOLISH {        # loopback, can be redefined in subclasses
    my $self = shift;

    return;
}

after DEMOLISH => sub {
    my $self = shift;

    $self->h_disconnect;

    return;
};

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::H::Role

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
