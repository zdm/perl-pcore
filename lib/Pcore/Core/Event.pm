package Pcore::Core::Event;

use Pcore -class;
use Pcore::Util::Scalar qw[weaken is_ref is_plain_arrayref];
use Pcore::Core::Event::Listener::Common;

has _bindings_cache => ( init_arg => undef );                # HashRef
has _listeners      => ( sub { {} }, init_arg => undef );    # HashRef
has _bindings       => ( sub { {} }, init_arg => undef );    # HashRef

sub get_listener ( $self, $id ) {
    return $self->{_listeners}->{$id};
}

sub listen_events ( $self, $bindings, $listener ) {

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

    $listener->bind($bindings);

    return $listener;
}

# TODO limit _bindings_cache size
sub get_key_bindings ( $self, $key, $cache = undef ) {
    $cache //= $self->{_bindings_cache} //= {};

    state $gen = sub ( $bindings, $path, $words ) {
        my $word = shift $words->@*;

        $bindings->{ $path . '*.#' }     = 1;
        $bindings->{ $path . "$word.#" } = 1;

        if ( $words->@* ) {
            __SUB__->( $bindings, $path . '*.',     [ $words->@* ] );
            __SUB__->( $bindings, $path . "$word.", [ $words->@* ] );
        }
        else {
            $bindings->{ $path . '*' } = 1;
            $bindings->{ $path . $word } = 1;
        }

        return;
    };

    if ( !exists $cache->{$key} ) {
        my $bindings = { $key => 1, '#' => 1 };

        $gen->( $bindings, q[], [ split /[.]/sm, $key ] );

        $cache->{$key} = [ keys $bindings->%* ];
    }

    return $cache->{$key};
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

    for my $listeners_group ( $self->{_bindings}->@{ $self->get_key_bindings($key)->@* } ) {
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
        [ 'test1', 'test2.*.log', 'test3.#' ],                       # bindings
        sub ( $ev ) {                                                # callback
            say dump $ev->{key};
            say dump $ev->{data};

            return;
        },
    );

    P->listen_events( 'log.test.*', 'stderr:' );                                                   # pipe
    P->listen_events( 'log.test.*', [ 'stderr:',      tmpl => "<: \$key :>$LF<: \$text :>" ] );    # pipe with params
    P->listen_events( 'log.test.*', [ 'file:123.log', tmpl => "<: \$key :>$LF<: \$text :>" ] );    # pipe with params

    P->fire_event( 'test.1234.aaa', $data );

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
