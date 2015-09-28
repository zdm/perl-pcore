package Pcore::AE::Handle::ProxyPool;

use Pcore qw[-class];
use Pcore::AE::Handle::ProxyPool::Storage;

has id => ( is => 'lazy', isa => Int, init_arg => undef );

has load_timeout          => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );     # 0 - don't re-load proxy sources
has connect_error_timeout => ( is => 'ro', isa => PositiveInt,       default => 180 );    # timeout for re-check disabled proxies
has max_connect_errors    => ( is => 'ro', isa => PositiveInt,       default => 5 );      # max. failed check attempts, after proxy will be removed
has ban_timeout           => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );
has max_threads_proxy     => ( is => 'ro', isa => PositiveOrZeroInt, default => 20 );
has max_threads_source    => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );
has maintanance_timeout   => ( is => 'ro', isa => PositiveInt,       default => 60 );

has _source => ( is => 'ro', isa => ArrayRef [ ConsumerOf ['Pcore::AE::Handle::ProxyPool::Source'] ], default => sub { [] }, init_arg => undef );
has _timer => ( is => 'ro', init_arg => undef );

has list => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has storage => ( is => 'lazy', isa => InstanceOf ['Pcore::AE::Handle::ProxyPool::Storage'], init_arg => undef );

has _waiting_callbacks => ( is => 'lazy', isa => ArrayRef, default => sub { [] }, init_arg => undef );

has is_proxy_pool => ( is => 'ro', default => 1, init_arg => undef );

no Pcore;

sub BUILD ( $self, $args ) {
    if ( $args->{source} ) {
        for my $source_args ( $args->{source}->@* ) {
            my %args = $source_args->%*;

            $args{pool} = $self;

            my $source = P->class->load( delete $args{class}, ns => 'Pcore::AE::Handle::ProxyPool::Source' )->new( \%args );

            # add source to the pool
            push $self->_source, $source;
        }
    }

    # create timer
    $self->{_timer} = AE::timer $self->maintanance_timeout, $self->maintanance_timeout, sub {
        $self->_maintenance;

        return;
    };

    $self->_maintenance;

    return;
}

sub _build_id ($self) {
    state $id = 0;

    return ++$id;
}

sub _build_storage ($self) {
    return Pcore::AE::Handle::ProxyPool::Storage->new( { pool_id => $self->id } );
}

# TODO throw events on release bans
sub _maintenance ($self) {

    # load sources
    for my $source ( $self->_source->@* ) {
        $source->load;
    }

    # clear connection errors
    my $time = time;

    if ( $self->storage->release_connect_error($time) ) {
        for my $proxy ( values $self->list->%* ) {
            if ( $proxy->{connect_error} && $proxy->{connect_error_time} <= $time ) {
                $proxy->{connect_error} = 0;

                $proxy->_on_status_change;
            }
        }
    }

    # release bans
    if ( $self->storage->release_ban($time) ) {

        # TODO throw events for waiting proxies
    }

    return;
}

sub add_proxy ( $self, $proxy ) {
    return if exists $self->list->{ $proxy->hostport };

    $self->list->{ $proxy->hostport } = $proxy;

    $self->storage->add_proxy($proxy);

    return;
}

# TODO
# improve search query, use ban table if needed
sub get_slot ( $self, $connect, @ ) {
    my $cb = $_[-1];

    my %args = (
        wait   => 1,
        ban_id => undef,    # check for ban
        @_[ 2 .. $#_ - 1 ],
    );

    $connect->[2] //= 'tcp';

    $connect->[3] //= $connect->[2] . q[_] . $connect->[1];

    if ( my $proxy = $self->_find_proxy($connect) ) {
        $cb->($proxy);
    }
    elsif ( !$args{wait} ) {
        $cb->(undef);
    }
    else {
        push $self->{_waiting_callbacks}->@*, [ $connect, $cb ];
    }

    return;
}

sub _on_status_change ($self) {
    my $tested_connect_id = {};

    for ( my $i = 0; $i <= $self->{_waiting_callbacks}->$#*; $i++ ) {
        my $slot = $self->{_waiting_callbacks}->[$i];

        my $connect = $slot->[0];

        next if $tested_connect_id->{ $connect->[3] };

        $tested_connect_id->{ $connect->[3] } = 1;

        if ( my $proxy = $self->_find_proxy($connect) ) {
            splice $self->{_waiting_callbacks}->@*, $i, 1;

            $slot->[1]->($proxy);

            last;
        }
    }

    return;
}

sub _find_proxy ( $self, $connect ) {
    state $q1 = $self->storage->dbh->query(
        <<"SQL"
            SELECT `proxy`.`hostport`
            FROM `proxy` LEFT JOIN `proxy_connect` ON ( `proxy`.`id` = `proxy_connect`.`proxy_id` AND `proxy_connect`.`connect_id` = ? )
            WHERE
                `proxy`.`connect_error` = 0
                AND `proxy`.`source_enabled` = 1
                AND `proxy`.`weight` <> 0
                AND ( `proxy_connect`.`proxy_type` IS NULL OR `proxy_connect`.`proxy_type` <> 0 )
            ORDER BY `proxy`.`weight` DESC
            LIMIT 1
SQL
    );

    if ( my $res = $q1->selectval( bind => [ $self->storage->_connect_id->{ $connect->[3] } ] ) ) {
        return $self->list->{ $res->$* };
    }
    else {
        return;
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 31, 76               │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 171                  │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 135                  │ ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Handle::ProxyPool

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
