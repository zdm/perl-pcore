package Pcore::AE::Handle::ProxyPool::Source;

use Pcore qw[-role];
use Pcore::Proxy::Pool::Proxy;
use Pcore::Proxy::Guard;

requires qw[load];

has pool => ( is => 'ro', isa => InstanceOf ['Pcore::Proxy::Pool'], required => 1, weak_ref => 1 );

has max_threads_source => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );     # max. num. of threads, allowed simultaneously to all proxies from this source, 0 - any num. of threads allowed
has max_threads_proxy  => ( is => 'ro', isa => PositiveOrZeroInt, default => 20 );
has max_threads_check  => ( is => 'ro', isa => PositiveInt,       default => 20 );    # max. allowed parallel check threads

has load_timeout => ( is => 'ro', isa => Maybe [PositiveOrZeroInt] );                 # undef - use global pool settings, 0 - do not reload

has is_multiproxy => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # proxy can not be banned

# lists
has _list_all      => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has _list_disabled => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has _list_active   => (
    is      => 'ro',
    isa     => HashRef,
    default => sub {
        {   any     => P->hash->randkey,
            http    => P->hash->randkey,
            connect => P->hash->randkey,
            https   => P->hash->randkey,
            socks   => P->hash->randkey,
            socks5  => P->hash->randkey,
            socks4  => P->hash->randkey,
            socks4a => P->hash->randkey,
        };
    },
    init_arg => undef
);
has _list_banned => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

has threads => ( is => 'ro', default => 0, init_arg => undef );    # current threads (running request through this source)

has _load_next_time   => ( is => 'ro', init_arg => undef );
has _load_in_progress => ( is => 'ro', init_arg => undef );

has _check_queue => ( is => 'ro', isa => ArrayRef, default => sub { [] }, init_arg => undef );
has _check_threads => ( is => 'ro', isa => PositiveOrZeroInt, default => 0, init_arg => undef );

around load => sub ( $orig, $self ) {

    # reload in progress
    return if $self->{_load_in_progress};

    # not reloadable and already was loaded
    return if !$self->{load_timeout} && $self->{_load_next_time};

    # timeout reached
    return if $self->{_load_next_time} && time < $self->{_load_next_time};

    $self->{_load_in_progress} = 1;

    $self->$orig(
        sub ($uris) {
            my $sources = $self->pool->_source;

            my $list_all = $self->_list_all;

            my $list_disabled = $self->_list_disabled;

            my $check_queue = $self->_check_queue;

            my $has_new_proxies;

            for my $uri ( $uris->@* ) {
                my $proxy = Pcore::Proxy::Pool::Proxy->new( $uri, $self );

                # proxy object wasn't created, generally due to uri parsing errors
                next if !$proxy;

                my $id = $proxy->id;

                my $add_proxy = 1;

                # add proxy to the pool if not exists
                for my $source ( $sources->@* ) {
                    if ( exists $source->_list_all->{$id} ) {
                        $add_proxy = 0;

                        last;
                    }
                }

                if ($add_proxy) {
                    $has_new_proxies = 1;

                    # add new proxy to all proxies list
                    $list_all->{$id} = $proxy;

                    # disable proxy
                    $self->disable_proxy($proxy);

                    # add proxy id to the check queue
                    $self->_push_check_queue($proxy);
                }
            }

            # update next source load timeout
            $self->{_load_next_time} = time + $self->{load_timeout};

            $self->{_load_in_progress} = 0;

            # run check if has new proxies
            $self->_check if $has_new_proxies;

            return;
        }
    );

    return;
};

no Pcore;

sub BUILD ( $self, $args ) {
    die q[You should specify "max_threads_source" or "max_threads_proxy"] if !$self->max_threads_source && !$self->max_threads_proxy;

    return;
}

sub _push_check_queue ( $self, $proxy ) {
    if ( !$proxy->{_check_enqueued} ) {
        $proxy->{_check_enqueued} = 1;

        $proxy->{_check_next_time} = 0;

        push $self->_check_queue->@*, $proxy->id;
    }

    return;
}

sub ban_proxy ( $self, $proxy, $key, $timeout = undef ) {

    # multiproxy can't be banned
    return if $self->is_multiproxy;

    $timeout //= $self->pool->{ban_timeout};

    # do not ban if no timeout specified
    return if !$timeout;

    my $id = $proxy->id;

    # proxy was removed
    return if !exists $self->_list_all->{$id};

    $self->_list_banned->{$key}->{$id} = time + $timeout;

    return;
}

sub _remove_proxy ( $self, $proxy ) {
    my $id = $proxy->id;

    # remove from pool
    delete $self->_list_all->{$id};

    # remove from disabled list
    delete $self->_list_disabled->{$id};

    # remove from active lists
    for ( values $self->_list_active->%* ) {
        delete $_->{$id};
    }

    # remove from ban lists
    my $list_banned = $self->_list_banned;

    for my $key ( keys $list_banned->%* ) {
        delete $list_banned->{$key}->{$id};

        delete $list_banned->{$key} if !keys $list_banned->{$key}->%*;
    }

    return;
}

sub disable_proxy ( $self, $proxy, $timeout = undef ) {
    my $id = $proxy->id;

    # proxy was removed
    return if !exists $self->_list_all->{$id};

    $timeout //= $self->pool->{check_timeout};

    $proxy->{is_enabled} = 0;

    # schedule next check time
    $proxy->{_check_next_time} = time + $timeout;

    # put into the disabled list
    $self->_list_disabled->{$id} = undef;

    # remove from all active lists
    for ( values $self->_list_active->%* ) {
        delete $_->{$id};
    }

    return;
}

sub _start_thread ( $self, $proxy ) {
    $proxy->{threads}++;

    $self->{threads}++;

    # do not deactivate proxy if max. proxy threads is not reached
    return if $self->{max_threads_proxy} && $proxy->{threads} < $self->{max_threads_proxy};

    my $id = $proxy->id;

    # remove from all active lists
    for ( values $self->_list_active->%* ) {
        delete $_->{$id};
    }

    return;
}

sub _finish_thread ( $self, $proxy ) {
    return if $proxy->{threads} < 1;

    $proxy->{threads}--;

    $self->{threads}--;

    $self->_activate_proxy($proxy);

    return;
}

sub _activate_proxy ( $self, $proxy ) {
    my $id = $proxy->id;

    # proxy was removed
    return if !exists $self->_list_all->{$id};

    # proxy is disabled
    return if exists $self->_list_disabled->{$id};

    # per proxy threads limit is exceeded
    return if $self->{max_threads_proxy} && $proxy->{threads} >= $self->{max_threads_proxy};

    # add proxy to the active lists
    my $list_active = $self->_list_active;

    state $lists = [qw[http connect https socks socks5 socks4 socks4a]];

    $list_active->{any}->{$id} = undef;

    for ( $lists->@* ) {
        $list_active->{$_}->{$id} = undef if $proxy->{ 'is_' . $_ };
    }

    $self->pool->on_proxy_activated( $self, $proxy );

    return;
}

sub on_check_timer ($self) {
    my $time = time;

    my $list_all = $self->_list_all;

    for my $id ( keys $self->_list_disabled->%* ) {
        my $proxy = $list_all->{$id};

        # proxy is not in the check queue yet
        if ( !$proxy->{_check_enqueued} ) {

            # proxy wasn't checked yet or check timeout is reached
            if ( !$proxy->{_check_next_time} || $time >= $proxy->{_check_next_time} ) {

                # put proxy id to the check queue
                $self->_push_check_queue($proxy);
            }
        }
    }

    $self->_check;

    return;
}

sub _check ($self) {

    # check if source has max threads limit and this limit is not exceeded
    return if $self->{max_threads_source} && $self->{threads} >= $self->{max_threads_source};

    # check if max. check threads limit is not exceeded
    return if $self->{_check_threads} >= $self->{max_threads_check};

    # fetch proxy id from check queue
    if ( my $id = shift $self->{_check_queue}->@* ) {
        my $proxy = $self->_list_all->{$id};

        $self->{_check_threads}++;

        $self->{threads}++;

        $proxy->{threads}++;

        $proxy->check(
            sub ($proxy) {
                $self->{_check_threads}--;

                $self->{threads}--;

                $proxy->{threads}--;

                $proxy->{_check_enqueued} = 0;

                if ( $proxy->{is_enabled} ) {

                    # reset failed check attempts counter
                    $proxy->{_check_failure} = 0;

                    # reset next check time
                    $proxy->{_check_next_time} = 0;

                    # remove from the disabled list
                    delete $self->_list_disabled->{ $proxy->id };

                    # try to activate proxy
                    $self->_activate_proxy($proxy);
                }
                else {
                    $proxy->{_check_failure}++;

                    my $pool = $self->pool;

                    # schedule next check time
                    $proxy->{_check_next_time} = time + $pool->{check_timeout};

                    # max. failed check attempts was reached
                    if ( $proxy->{_check_failure} >= $pool->{check_failure} ) {

                        # remove proxy
                        $self->_remove_proxy($proxy);
                    }
                }

                $self->_check;

                return;
            }
        );

        $self->_check if $self->{_check_queue}->@*;
    }

    return;
}

sub get_weight ( $self, $list ) {
    $self->_check;

    # source has no active proxies
    return if !scalar $self->_list_active->{$list}->%*;

    if ( $self->{max_threads_source} ) {

        # max. threads per source exceeded
        return if $self->{threads} >= $self->{max_threads_source};

        return $self->{max_threads_source} - $self->{threads};
    }
    else {
        return $self->_list_active->{'any'}->%* * $self->{max_threads_proxy} - $self->{threads};
    }
}

sub get_proxy ( $self, $list ) {
    if ( my $id = $self->_list_active->{$list}->rand_key ) {
        my $proxy = $self->_list_all->{$id};

        $self->_start_thread($proxy);

        return Pcore::Proxy::Guard->new( { _guard_proxy => $proxy } );
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
## │    3 │ 63                   │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 171, 178, 181, 204,  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 222, 274, 368, 378   │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 229                  │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_finish_thread' declared but not    │
## │      │                      │ used                                                                                                           │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 22                   │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Handle::ProxyPool::Source

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
