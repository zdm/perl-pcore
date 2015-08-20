package Pcore::AnyEvent::Proxy::Pool;

use Pcore qw[-class];
use Pcore::AnyEvent::Proxy;

has load_timeout    => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );     # 0 - don't load automatically
has disable_timeout => ( is => 'ro', isa => PositiveOrZeroInt, default => 180 );    # 0 - don't disable proxy, if timeout isn't specified
has ban_timeout     => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );     # 0 - don't ban proxy, if timeout isn't specified
has clear_on_load   => ( is => 'ro', isa => Bool,              default => 0 );      # clear proxy pool before load new proxies

has _source => ( is => 'ro', isa => ArrayRef [ ConsumerOf ['Pcore::AnyEvent::Proxy::Source'] ], default => sub { [] }, init_arg => undef );
has _pool         => ( is => 'lazy', isa => HashRef, default => sub { {} }, clearer => 1, init_arg => undef );
has _not_active   => ( is => 'lazy', isa => HashRef, default => sub { {} }, clearer => 1, init_arg => undef );
has _active_lists => ( is => 'lazy', isa => HashRef, default => sub { {} }, clearer => 1, init_arg => undef );

has _last_loaded                => ( is => 'rw', isa => PositiveOrZeroInt, default => 0, init_arg => undef );
has _load_in_progress           => ( is => 'rw', isa => Bool,              default => 0, init_arg => undef );
has _next_disabled_release_time => ( is => 'rw', isa => PositiveOrZeroInt, default => 0, init_arg => undef );
has _next_banned_release_time   => ( is => 'rw', isa => PositiveOrZeroInt, default => 0, init_arg => undef );

no Pcore;

sub BUILD {
    my $self = shift;
    my $args = shift;

    if ( $args->{source} ) {
        for my $source ( $args->{source}->@* ) {
            my $class = delete $source->{class};

            my %args = $source->%*;

            $args{_pool} = $self;

            push $self->_source, P->class->load( $class, ns => 'Pcore::AnyEvent::Proxy::Source' )->new( \%args );
        }
    }

    return;
}

sub update_proxy_status ( $self, $proxy ) {
    return unless exists $self->_pool->{ $proxy->id };

    my $id = $proxy->id;

    my $active_lists = $self->_active_lists;

    if ( !$proxy->is_active ) {

        # add proxy id to not_active list
        $self->_not_active->{$id} = 1;

        # remove proxy id from active lists
        for my $active_list ( $proxy->_active_lists->@* ) {
            delete $active_lists->{$active_list}->{$id};
        }

        if ( $proxy->is_disabled ) {
            $self->_next_disabled_release_time( $proxy->is_disabled ) if !$self->_next_disabled_release_time || $self->_next_disabled_release_time > $proxy->is_disabled;
        }

        if ( $proxy->is_banned ) {
            $self->_next_banned_release_time( $proxy->is_banned ) if !$self->_next_banned_release_time || $self->_next_banned_release_time > $proxy->is_banned;
        }
    }
    else {

        # remove proxy id from not_active list
        delete $self->_not_active->{$id};

        # add proxy to active lists
        for my $active_list ( $proxy->_active_lists->@* ) {
            $active_lists->{$active_list}->{$id} = 1;
        }
    }

    return;
}

sub clear ($self) {
    $self->_clear_pool;

    $self->_clear_not_active;

    $self->_clear_active_lists;

    return;
}

sub _load ( $self, $cb ) {

    # retrun, if load process is already running or auto loading disabled
    if ( $self->_load_in_progress || ( $self->_last_loaded && !$self->load_timeout ) ) {
        $cb->();

        return;
    }

    # retrun, if timeout not reached
    if ( $self->_last_loaded + $self->load_timeout > time ) {
        $cb->();

        return;
    }

    $self->_load_in_progress(1);

    my $temp_pool = [];

    my $cv = AE::cv {
        $self->clear if $self->clear_on_load;

        for my $proxy ( $temp_pool->@* ) {
            if ( !exists $self->_pool->{ $proxy->id } ) {
                $self->_pool->{ $proxy->id } = $proxy;

                $self->update_proxy_status($proxy);
            }
        }

        $self->_last_loaded(time);

        $self->_load_in_progress(0);

        $cb->();

        return;
    };

    for my $source ( $self->_source->@* ) {
        $cv->begin;

        $source->load( $cv, $temp_pool );
    }

    return;
}

sub release ($self) {
    my $time             = time;
    my $release_disabled = $self->_next_disabled_release_time && $self->_next_disabled_release_time <= time ? 1 : 0;
    my $release_banned   = $self->_next_banned_release_time && $self->_next_banned_release_time <= time ? 1 : 0;

    if ( $release_disabled || $release_banned ) {
        $self->_next_disabled_release_time(0) if $release_disabled;

        $self->_next_banned_release_time(0) if $release_banned;

        for my $id ( keys $self->_not_active->%* ) {
            my $proxy = $self->_pool->{$id};

            if ($release_disabled) {
                if ( $proxy->is_disabled ) {
                    if ( $proxy->is_disabled <= $time ) {
                        $proxy->enable;
                    }
                    else {
                        $self->_next_disabled_release_time( $proxy->is_disabled ) if !$self->_next_disabled_release_time || $self->_next_disabled_release_time > $proxy->is_disabled;
                    }
                }
            }

            if ($release_banned) {
                if ( $proxy->is_banned ) {
                    if ( $proxy->is_banned <= $time ) {
                        $proxy->unban;
                    }
                    else {
                        $self->_next_banned_release_time( $proxy->is_banned ) if !$self->_next_banned_release_time || $self->_next_banned_release_time > $proxy->is_banned;
                    }
                }
            }
        }
    }

    return;
}

sub get_proxy ( $self, $lists, $cb ) {
    $lists = [$lists] if ref $lists ne 'ARRAY';

    my $load_cb = sub {
        $self->release;

        my $proxy;

        for my $list ( $lists->@* ) {
            if ( my @ids = keys $self->_active_lists->{$list}->%* ) {
                my $id = $ids[ rand @ids ];

                $proxy = $self->_pool->{$id};

                $proxy->start_thread;

                last;
            }
        }

        $cb->($proxy);

        return;
    };

    $self->_load($load_cb);

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 31, 150, 189         │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 140                  │ Subroutines::ProhibitExcessComplexity - Subroutine "release" with high complexity score (22)                   │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
