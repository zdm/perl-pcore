package Pcore::Core::Event;

use Pcore -class;
use Pcore::Util::Scalar qw[weaken];
use Pcore::Core::Event::Listener;

has listeners => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

sub listen_event ( $self, $keys, $cb ) {
    $keys = [$keys] if ref $keys ne 'ARRAY';

    my $listener = Pcore::Core::Event::Listener->new(
        {   event => $self,
            keys  => $keys,
            cb    => $cb,
        }
    );

    my $wantarray = defined wantarray;

    for my $key ( $keys->@* ) {
        push $self->{listeners}->{$key}->@*, $listener;

        weaken $self->{listeners}->{$key}->[-1] if $wantarray;
    }

    return $wantarray ? $listener : ();
}

sub has_listeners ( $self, $keys ) {
    $keys = [$keys] if ref $keys ne 'ARRAY';

    for my $key ( $keys->@* ) {
        return 1 if exists $self->{listeners}->{$key};
    }

    return 0;
}

sub fire_event ( $self, $key, $data = undef ) {
    if ( my $listeners = $self->{listeners}->{$key} ) {
        for my $listener ( $listeners->@* ) {
            $listener->{cb}->( $key, $data );
        }
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Event - Pcore event broker

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
