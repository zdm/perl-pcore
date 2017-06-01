package Pcore::Core::Event;

use Pcore -class;
use Pcore::Util::Scalar qw[weaken];
use Pcore::Core::Event::Listener;
use Time::HiRes qw[];

has listeners => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has senders   => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has mask_re   => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

sub listen_events ( $self, $masks, @listeners ) {
    my $guard = defined wantarray ? [] : ();

    $masks = [$masks] if ref $masks ne 'ARRAY';

    for my $mask ( $masks->@* ) {

        # get matched senders
        my $senders = [ grep { $self->_match_events( $mask, $_ ) } keys $self->{senders}->%* ];

        # create listeners
        for my $listen (@listeners) {
            my $cb;

            if ( !ref $listen ) {
                my $uri = Pcore->uri($listen);

                my $class = Pcore->class->load( $uri->scheme, ns => 'Pcore::Core::Event::Listener::Pipe' );

                $cb = $class->new( { uri => $uri } );
            }
            elsif ( ref $listen eq 'ARRAY' ) {
                my ( $uri, %args ) = $listen->@*;

                $args{uri} = Pcore->uri($uri);

                my $class = Pcore->class->load( $args{uri}->scheme, ns => 'Pcore::Core::Event::Listener::Pipe' );

                $cb = $class->new( \%args );
            }
            elsif ( ref $listen eq 'CODE' ) {
                $cb = $listen;
            }
            else {
                die q[Invalid listener type];
            }

            my $listener = Pcore::Core::Event::Listener->new(
                {   broker => $self,
                    masks  => $masks,
                    cb     => $cb,
                }
            );

            $self->{listeners}->{$mask}->{ $listener->{id} } = $listener;

            if ($guard) {
                push $guard->@*, $listener;

                weaken $self->{listeners}->{$mask}->{ $listener->{id} };
            }

            # add listener to matched senders
            for my $key ( $senders->@* ) {
                $self->{senders}->{$key}->{ $listener->{id} } = $listener;

                weaken $self->{senders}->{$key}->{ $listener->{id} };
            }
        }
    }

    return $guard;
}

sub has_listeners ( $self, $key ) {
    $self->_register_sender($key) if !exists $self->{senders}->{$key};

    return $self->{senders}->{$key}->%* ? 1 : 0;
}

sub _register_sender ( $self, $key ) {
    return if exists $self->{senders}->{$key};

    my $sender = $self->{senders}->{$key} = {};

    for my $mask ( keys $self->{listeners}->%* ) {
        if ( $self->_match_events( $mask, $key ) ) {
            for my $listener ( values $self->{listeners}->{$mask}->%* ) {
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
sub _match_events ( $self, $mask, $key ) {
    if ( index( $mask, '*' ) != -1 || index( $mask, '#' ) != -1 ) {
        if ( !exists $self->{mask_re}->{$mask} ) {
            my $re = quotemeta $mask;

            $re =~ s/\\[#]/.*?/smg;

            $re =~ s/\\[*]/[^.]+/smg;

            $self->{mask_re}->{$mask} = qr/\A$re\z/sm;
        }

        return $key =~ $self->{mask_re}->{$mask};
    }
    else {
        return $mask eq $key;
    }

    return;
}

# TODO remove key from listener call
sub forward_event ( $self, $ev ) {
    $self->_register_sender( $ev->{key} ) if !exists $self->{senders}->{ $ev->{key} };

    for my $listener ( values $self->{senders}->{ $ev->{key} }->%* ) {
        $listener->{cb}->( $ev->{key}, $ev );
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
