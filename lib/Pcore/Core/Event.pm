package Pcore::Core::Event;

use Pcore -class;
use Pcore::Util::Scalar qw[weaken is_ref is_plain_arrayref];
use Pcore::Core::Event::Listener::Common;

has _key_masks_cache => ( init_arg => undef );                # HashRef
has _listeners       => ( sub { {} }, init_arg => undef );    # HashRef
has _mask_listener   => ( sub { {} }, init_arg => undef );    # HashRef

sub get_listener ( $self, $id ) {
    return $self->{_listeners}->{$id};
}

sub listen_events ( $self, $masks, $listener ) {

    # create listener
    if ( !is_ref $listener) {
        my $uri = Pcore->uri($listener);

        $listener = Pcore->class->load( $uri->{scheme}, ns => 'Pcore::Core::Event::Listener' )->new(
            broker => $self,
            uri    => $uri
        );
    }
    elsif ( is_plain_arrayref $listener) {
        my $uri = Pcore->uri( shift $listener->@* );

        $listener = Pcore->class->load( $uri->{scheme}, ns => 'Pcore::Core::Event::Listener' )->new(
            $listener->@*,
            broker => $self,
            uri    => $uri
        );
    }
    else {
        $listener = Pcore::Core::Event::Listener::Common->new(
            broker => $self,
            cb     => $listener
        );
    }

    if ( exists $self->{_listeners}->{ $listener->{id} } ) {
        $listener = $self->{_listeners}->{ $listener->{id} };
    }
    else {
        $self->{_listeners}->{ $listener->{id} } = $listener;

        weaken $self->{_listeners}->{ $listener->{id} } if defined wantarray;
    }

    $listener->add_masks($masks);

    return $listener;
}

sub get_key_masks ( $self, $mask, $cache = undef ) {
    $cache //= $self->{_key_masks_cache};

    state $gen = sub ( $keys, $path, $words ) {
        my $word = shift $words->@*;

        $keys->{ $path . '*.#' }     = 1;
        $keys->{ $path . "$word.#" } = 1;

        if ( $words->@* ) {
            __SUB__->( $keys, $path . '*.',     [ $words->@* ] );
            __SUB__->( $keys, $path . "$word.", [ $words->@* ] );
        }
        else {
            $keys->{ $path . '*' } = 1;
            $keys->{ $path . $word } = 1;
        }

        return;
    };

    if ( !exists $cache->{$mask} ) {
        my $keys = { $mask => 1, '#' => 1 };

        $gen->( $keys, q[], [ split /[.]/sm, $mask ] );

        $cache->{$mask} = [ sort keys $keys->%* ];
    }

    return $cache->{$mask};
}

sub has_listeners ( $self, $key ) {
    return scalar $self->_get_listeners($key)->@*;
}

sub forward_event ( $self, $ev ) {
    for my $listener ( $self->_get_listeners( $ev->{key} )->@* ) { $listener->forward_event($ev) }

    return;
}

sub _get_listeners ( $self, $key ) {
    my $listeners;

    for my $listeners_group ( $self->{_mask_listener}->@{ $self->get_key_masks($key)->@* } ) {
        next if !defined $listeners_group;

        for my $listener ( values $listeners_group->%* ) {
            next if $listener->{is_suspended};

            $listeners->{ $listener->{id} } = $listener;
        }
    }

    return [ values $listeners->%* ];
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Event - Pcore event broker

=head1 SYNOPSIS

    P->listen_events(
        [ 'TEST1', 'TEST2.*.LOG', 'TEST3.#' ],                       # listen masks
        sub ( $ev ) {                                                # callback
            say dump $ev->{key};
            say dump $ev->{data};

            return;
        },
    );

    P->listen_events( 'log.test', 'stderr:' );                                                   # pipe
    P->listen_events( 'log.test', [ 'stderr:',      tmpl => "<: \$key :>$LF<: \$text :>" ] );    # pipe with params
    P->listen_events( 'log.test', [ 'file:123.log', tmpl => "<: \$key :>$LF<: \$text :>" ] );    # pipe with params

    P->fire_event( 'TEST.1234.AAA', $data );

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head2 fire_event( $key, $data ) - fire event

$key - event key, special symbols can be used:

* (star) can substitute for exactly one word;

# (hash) can substitute for zero or more words;

where word is /[^.]/

=head1 SEE ALSO

=cut
