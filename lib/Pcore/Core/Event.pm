package Pcore::Core::Event;

use Pcore -class;
use Pcore::Util::Scalar qw[weaken];
use Pcore::Core::Event::Listener;
use Time::HiRes qw[];

has listeners => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

sub listen_events ( $self, $events, $cb ) {
    $events = [$events] if ref $events ne 'ARRAY';

    my $listener = Pcore::Core::Event::Listener->new(
        {   broker => $self,
            events => $events,
            cb     => $cb,
        }
    );

    my $wantarray = defined wantarray;

    for my $event ( $events->@* ) {
        push $self->{listeners}->{$event}->@*, $listener;

        weaken $self->{listeners}->{$event}->[-1] if $wantarray;
    }

    return $wantarray ? $listener : ();
}

sub has_listeners ( $self, $events ) {
    $events = [$events] if ref $events ne 'ARRAY';

    for my $event ( $events->@* ) {
        return 1 if exists $self->{listeners}->{$event};
    }

    return 0;
}

sub fire_event ( $self, $event, $data = undef ) {
    if ( my $listeners = $self->{listeners}->{$event} ) {
        for my $listener ( $listeners->@* ) {
            $listener->{cb}->( $event, $data );
        }
    }

    return;
}

# LOG namespace
sub create_logpipe ( $self, $channel, @pipes ) {
    my $guard = defined wantarray ? [] : ();

    my $event = ["LOG.$channel"];

    for my $pipe (@pipes) {
        if ( !ref $pipe ) {
            my $uri = Pcore->uri($pipe);

            my $class = Pcore->class->load( $uri->scheme, ns => 'Pcore::Core::Event::Log::Pipe' );

            if ($guard) {
                push $guard->@*, $self->listen_events( $event, $class->new( { uri => $uri } ) );
            }
            else {
                $self->listen_events( $event, $class->new( { uri => $uri } ) );
            }
        }
        elsif ( ref $pipe eq 'ARRAY' ) {
            my ( $uri, %args ) = $pipe->@*;

            $args{uri} = Pcore->uri($uri);

            my $class = Pcore->class->load( $args{uri}->scheme, ns => 'Pcore::Core::Event::Log::Pipe' );

            if ($guard) {
                push $guard->@*, $self->listen_events( $event, $class->new( \%args ) );
            }
            else {
                $self->listen_events( $event, $class->new( \%args ) );
            }
        }
        elsif ( ref $pipe eq 'CODE' ) {
            if ($guard) {
                push $guard->@*, $self->listen_events( $event, $pipe );
            }
            else {
                $self->listen_events( $event, $pipe );
            }
        }
        else {
            die q[Invalid log pipe type];
        }
    }

    return $guard;
}

sub sendlog ( $self, $channel, $title, $body = undef ) {
    return if !$self->has_listeners("LOG.$channel");

    my $data;

    ( $data->{channel}, $data->{level} ) = split /[.]/sm, $channel, 2;

    die q[Log level must be specified] unless $data->{level};

    \$data->{title} = \$title;

    $data->{timestamp} = Time::HiRes::time();

    if ( ref $body ) {
        $data->{body} = dump $body;
    }
    else {
        \$data->{body} = \$body;
    }

    $self->fire_event( "LOG.$channel", $data );

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
