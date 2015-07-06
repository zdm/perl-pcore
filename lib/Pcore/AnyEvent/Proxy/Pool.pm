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
            $self->_add_source( delete $source->{class}, $source->%* );
        }
    }

    return;
}

sub _add_source {
    my $self   = shift;
    my $source = shift;
    my %args   = @_;

    $args{_pool} = $self;

    my $class = P->class->load( $source, ns => 'Pcore::AnyEvent::Proxy::Source' );

    push $self->_source, $class->new( \%args );

    return;
}

sub _add_proxy {
    my $self  = shift;
    my $proxy = shift;

    if ( !exists $self->_pool->{ $proxy->id } ) {
        $self->_pool->{ $proxy->id } = $proxy;

        $self->update_proxy_status($proxy);
    }

    return $proxy;
}

sub update_proxy_status {
    my $self  = shift;
    my $proxy = shift;

    return unless exists $self->_pool->{ $proxy->id };

    if ( !$proxy->is_active ) {
        my $id           = $proxy->id;
        my $active_lists = $self->_active_lists;

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
        my $id           = $proxy->id;
        my $active_lists = $self->_active_lists;

        # remove proxy id from not_active list
        delete $self->_not_active->{$id};

        # add proxy to active lists
        for my $active_list ( $proxy->_active_lists->@* ) {
            $active_lists->{$active_list}->{$id} = 1;
        }
    }

    return;
}

sub clear {
    my $self = shift;

    $self->_clear_pool;

    $self->_clear_not_active;

    $self->_clear_active_lists;

    return;
}

sub load {
    my $self = shift;
    my %args = (
        blocking => 0,
        @_,
    );

    # don't load if load process running or auto loading disabled
    return if $self->_load_in_progress || ( $self->_last_loaded && !$self->load_timeout );

    # don't load if timeout not reached
    return if $self->_last_loaded + $self->load_timeout > time;

    $self->_load_in_progress(1);

    my $cv = AnyEvent->condvar;

    my $temp_pool = [];

    $cv->begin(
        sub {
            $self->clear if $self->clear_on_load;

            for my $proxy ( $temp_pool->@* ) {
                $self->_add_proxy($proxy);
            }

            $cv->send if $args{blocking};

            $self->_last_loaded(time);

            $self->_load_in_progress(0);

            return;
        }
    );

    for my $source ( $self->_source->@* ) {
        $source->load( $cv, $temp_pool );
    }

    $cv->end;

    $cv->recv if $args{blocking};

    return;
}

sub release {
    my $self = shift;

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

sub get_proxy {
    my $self = shift;
    my %args = (
        list     => 'http',    # http, https, ...
        selector => 'rand',    # rand, threads, requests
        @_,
    );

    $self->load;

    $self->release;

    if ( my @ids = keys $self->_active_lists->{ $args{list} }->%* ) {
        my $id;

        if ( $args{selector} eq 'threads' ) {    # min. threads selector
            $id = [ sort { $self->_pool->{$a}->threads <=> $self->_pool->{$b}->threads } @ids ]->[0];
        }
        elsif ( $args{selector} eq 'requests' ) {    # min. total requests selector
            $id = [ sort { $self->_pool->{$a}->total_requests <=> $self->_pool->{$b}->total_requests } @ids ]->[0];
        }
        else {                                       # random selector
            $id = $ids[ rand @ids ];
        }

        my $proxy = $self->_pool->{$id};

        $proxy->start_thread;

        return $proxy;
    }
    else {
        return;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 29, 177, 219         │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 165                  │ Subroutines::ProhibitExcessComplexity - Subroutine "release" with high complexity score (22)                   │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
