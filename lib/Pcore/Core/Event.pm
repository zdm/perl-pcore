package Pcore::Core::Event;

use Pcore -class;
use Pcore::Util::Scalar qw[weaken];
use Pcore::Core::Event::Listener;
use Time::HiRes qw[];

has listeners    => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has senders      => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has listeners_re => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

sub listen_events ( $self, $events, $cb ) {
    $events = [$events] if ref $events ne 'ARRAY';

    my $listener = Pcore::Core::Event::Listener->new(
        {   broker => $self,
            events => $events,
            cb     => $cb,
        }
    );

    my $wantarray = defined wantarray;

    for my $listen_ev ( $events->@* ) {
        $self->{listeners}->{$listen_ev}->{ $listener->{id} } = $listener;

        weaken $self->{listeners}->{$listen_ev}->{ $listener->{id} } if $wantarray;

        # add listener to matched senders
        for my $send_ev ( keys $self->{senders}->%* ) {
            if ( $self->_match_events( $listen_ev, $send_ev ) ) {
                $self->{senders}->{$send_ev}->{ $listener->{id} } = $listener;

                weaken $self->{senders}->{$send_ev}->{ $listener->{id} };
            }
        }
    }

    return $wantarray ? $listener : ();
}

sub has_listeners ( $self, $event ) {
    $self->_register_sender($event) if !exists $self->{senders}->{$event};

    return $self->{senders}->{$event}->%* ? 1 : 0;
}

sub _register_sender ( $self, $send_ev ) {
    return if exists $self->{senders}->{$send_ev};

    my $sender = $self->{senders}->{$send_ev} = {};

    for my $listen_ev ( keys $self->{listeners}->%* ) {
        if ( $self->_match_events( $listen_ev, $send_ev ) ) {
            for my $listener ( values $self->{listeners}->{$listen_ev}->%* ) {
                if ( !exists $sender->{ $listener->{id} } ) {
                    $sender->{ $listener->{id} } = $listener;

                    weaken $sender->{ $listener->{id} };
                }
            }
        }
    }

    return;
}

# send_ev always without wildcards
# listen_ev could contain wildcards:
# * (star) can substitute for exactly one word
# # (hash) can substitute for zero or more words
# word = [^.]
sub _match_events ( $self, $listen_ev, $send_ev ) {
    if ( index( $listen_ev, '*' ) != -1 || index( $listen_ev, '#' ) != -1 ) {
        if ( !exists $self->{listeners_re}->{$listen_ev} ) {
            my $re = quotemeta $listen_ev;

            $re =~ s/\\[#]/.*?/smg;

            $re =~ s/\\[*]/[^.]+/smg;

            $self->{listeners_re}->{$listen_ev} = qr/\A$re\z/sm;
        }

        return $send_ev =~ $self->{listeners_re}->{$listen_ev} ? 1 : 0;
    }
    elsif ( $listen_ev eq $send_ev ) {
        return 1;
    }

    return;
}

sub fire_event ( $self, $event, $data = undef ) {
    $self->_register_sender($event) if !exists $self->{senders}->{$event};

    for my $listener ( values $self->{senders}->{$event}->%* ) {
        $listener->{cb}->( $event, $data );
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

            my $class = Pcore->class->load( $uri->scheme, ns => 'Pcore::Core::Event::Listener::Pipe' );

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

            my $class = Pcore->class->load( $args{uri}->scheme, ns => 'Pcore::Core::Event::Listener::Pipe' );

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
