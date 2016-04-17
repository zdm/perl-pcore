package Pcore::Core::H::Cache;

use Pcore -class, -autoload;
use Pcore::Util::Scalar qw[blessed isweak weaken];

has _h_cache => ( is => 'lazy', isa => HashRef [ ConsumerOf ['Pcore::Core::H::Role'] ], init_arg => undef );
has _h_supported_events => ( is => 'lazy', isa => HashRef, init_arg => undef );

sub _build__h_cache ($self) {
    P->EV->register( 'CORE#PROC::BEFORE_FORK' => \&_h_ev_before_fork, args => [ \$self ] );

    return {};
}

sub _build__h_supported_events ($self) {
    return {
        PID_CHANGE  => 1,
        BEFORE_FORK => 1,
    };
}

sub _h_ev_before_fork ( $ev, $self ) {
    $self = $self->$*;

    if ($self) {
        $self->run_event('BEFORE_FORK');
    }
    else {
        $ev->remove;
    }

    return;
}

sub run_event ( $self, $event ) {
    for my $id ( grep { $self->_h_cache->{$_}->{event} && $self->_h_cache->{$_}->{event} eq $event } keys %{ $self->_h_cache } ) {
        if ( my $h = $self->_get($id) ) {
            $h->h_disconnect;
        }
    }

    return;
}

sub _get ( $self, $id ) {
    my $cache_id = $self->_h_cache->{$id};

    if ( !$cache_id->{h} ) {
        delete $self->_h_cache->{$id};

        return;
    }
    else {
        if ( $cache_id->{event} && $cache_id->{event} eq 'PID_CHANGE' ) {
            if ( $cache_id->{pid} && $cache_id->{pid} ne $$ ) {
                $cache_id->{h}->h_disconnect;

                $cache_id->{pid} = $$;
            }
        }

        return $cache_id->{h};
    }
}

sub _AUTOLOAD ( $self, $method, @ ) {
    die qq[Handle "$method" not exists in cache] unless $self->_h_cache->{$method};

    my $quoted = quotemeta $method;

    return <<"PERL";
        sub (\$self) {
            if ( my \$h = \$self->_get(q[$method]) ) {
                return \$h;
            }
            else {
                die qq[Handle "$quoted" was removed from cache];
            }
        };
PERL
}

# PUBLIC
sub add ( $self, $id, $class, %args ) {

    # handle object ref can be weak if not exists in cache (new handle) or already weaken
    my $can_weak = $self->_h_cache->{$id}->{h} ? isweak( $self->_h_cache->{$id}->{h} ) : 1;

    my $h;

    if ( blessed($class) ) {
        $h     = $class;
        $class = ref $class;
    }
    else {
        $h = P->class->load( $class, ns => 'Pcore::Handle', does => 'Pcore::Core::H::Role' )->new( \%args );
    }

    die qq[Handle "$class" event "] . $h->h_disconnect_on . q[" not supported by cache] if $h->h_disconnect_on && !$self->_h_supported_events->{ $h->h_disconnect_on };

    $self->_h_cache->{$id} = {
        h     => $h,
        event => $h->h_disconnect_on,
        pid   => $$,
    };

    if ( defined wantarray ) {
        weaken( $self->_h_cache->{$id}->{h} ) if $can_weak;

        return $h;
    }
    else {
        return;
    }
}

sub remove ( $self, $id ) {
    delete $self->_h_cache->{$id};

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 66                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_AUTOLOAD' declared but not used    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::H::Cache

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
