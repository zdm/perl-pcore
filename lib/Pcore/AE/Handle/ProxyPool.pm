package Pcore::AE::Handle::ProxyPool;

use Pcore qw[-class];

has load_timeout          => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );     # 0 - don't re-load proxy sources
has connect_error_timeout => ( is => 'ro', isa => PositiveInt,       default => 180 );    # timeout for re-check disabled proxies
has max_connect_errors    => ( is => 'ro', isa => PositiveInt,       default => 3 );      # max. failed check attempts, after proxy will be removed
has ban_timeout           => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );
has max_threads_proxy     => ( is => 'ro', isa => PositiveOrZeroInt, default => 20 );
has max_threads_source    => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );

# TODO define automatically
has purge_timeout => ( is => 'ro', isa => PositiveInt, default => 180 );                  # timeout for re-check disabled proxies

has _source => ( is => 'ro', isa => ArrayRef [ ConsumerOf ['Pcore::AE::Handle::ProxyPool::Source'] ], default => sub { [] }, init_arg => undef );
has _load_timer  => ( is => 'ro', init_arg => undef );
has _purge_timer => ( is => 'ro', init_arg => undef );

has dbh => ( is => 'lazy', isa => Object, init_arg => undef );
has list => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

no Pcore;

# TODO automatically select purge timeout
sub BUILD ( $self, $args ) {
    if ( $args->{source} ) {
        my $min_source_load_timeout = 0;

        for my $source_args ( $args->{source}->@* ) {
            my %args = $source_args->%*;

            $args{pool} = $self;

            my $source = P->class->load( delete $args{class}, ns => 'Pcore::AE::Handle::ProxyPool::Source' )->new( \%args );

            # add source to the pool
            push $self->_source, $source;

            # define minimal source load interval, if source is reloadable
            if ( $source->load_timeout ) {
                if ( !$min_source_load_timeout ) {
                    $min_source_load_timeout = $source->load_timeout;
                }
                elsif ( $source->load_timeout < $min_source_load_timeout ) {
                    $min_source_load_timeout = $source->load_timeout;
                }
            }
        }

        if ($min_source_load_timeout) {

            # create reload timer
            $self->{_load_timer} = AE::timer 0, $min_source_load_timeout, sub {
                $self->_on_load_timer;

                return;
            };
        }
        else {

            # all sources is not reloadable, run load once
            $self->_on_load_timer;
        }
    }

    # create check timer
    $self->{_purge_timer} = AE::timer $self->purge_timeout, $self->purge_timeout, sub {
        $self->_on_purge_timer;

        return;
    };

    return;
}

sub _build_dbh ($self) {
    unlink 'proxy-pool.sqlite' or 1;

    H->add(
        __proxy_pool => 'SQLite',

        # addr => 'memory://',
        addr => 'file:./proxy-pool.sqlite',
    );

    my $dbh = H->__proxy_pool;

    my $ddl = $dbh->ddl;

    $ddl->add_changeset(
        id  => 1,
        sql => <<'SQL'
            CREATE TABLE IF NOT EXISTS `proxy` (
                `pool_id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `id` TEXT NOT NULL,
                `source_id` INTEGER NOT NULL,
                `source_can_connect` INTEGER NOT NULL,
                `connect_error` INTEGER NOT NULL DEFAULT 0,
                `connect_error_time` INTEGER NOT NULL DEFAULT 0,
                `threads` INTEGER NOT NULL DEFAULT 0,
                `max_threads` INTEGER NOT NULL
            );

            CREATE UNIQUE INDEX IF NOT EXISTS `idx_proxy_id` ON `proxy` (`id` ASC);

            CREATE INDEX IF NOT EXISTS `idx_proxy_connect_error_time` ON `proxy` (`connect_error` DESC, `connect_error_time` ASC);

            -- CREATE INDEX IF NOT EXISTS `idx_proxy_disabled` ON `proxy` (`disabled` DESC);

            -- CREATE INDEX IF NOT EXISTS `idx_proxy_threads` ON `proxy` (`threads` ASC);

            -- CREATE INDEX IF NOT EXISTS `idx_proxy_disabled_threads` ON `proxy` (`disabled` DESC, `threads` ASC);
SQL
    );

    $ddl->upgrade;

    return $dbh;
}

sub _on_load_timer ($self) {
    for my $source ( $self->_source->@* ) {
        $source->load;
    }

    return;
}

# TODO throw event, some proxies was enabled
# TODO release banned proxies
sub _on_purge_timer ($self) {
    state $q1 = $self->dbh->query('UPDATE `proxy` SET `connect_error` = 0 WHERE `connect_error` = 1 AND `connect_error_time` <= ?');

    my $time = time;

    if ( $q1->do( bind => [$time] ) ) {
        for my $proxy ( values $self->list->%* ) {
            $proxy->{connect_error} = 0 if $proxy->{connect_error} && $proxy->{connect_error_time} <= $time;
        }
    }

    return;
}

sub add_proxy ( $self, $proxy ) {
    return if exists $self->list->{ $proxy->id };

    state $q1 = $self->dbh->query('INSERT INTO `proxy` (`id`, `source_id`, `source_can_connect`, `max_threads`) VALUES (?, ?, ?, ?)');

    $q1->do( bind => [ $proxy->id, $proxy->source->id, $proxy->source->can_connect, $proxy->max_threads ] );

    $proxy->{pool_id} = $self->dbh->last_insert_id;

    $self->list->{ $proxy->id } = $proxy;

    return;
}

# sub add_connect_id ( $self, $connect_id ) {
#     return if exists $CONNECT_ID->{$connect_id};
#
#     $CONNECT_ID->{connect_id} = 1;
#
#     my $sql = <<"SQL";
#         ALTER TABLE `proxy` ADD COLUMN `$connect_id`;
#
#         CREATE INDEX IF NOT EXISTS `idx_proxy_$connect_id` ON `proxy` (`$connect_id` DESC);
# SQL
#
#     $self->dbh->do($sql);
#
#     return;
# }

# TODO
sub get_proxy ( $self, $connect, $cb ) {
    $cb->( $self->list->{'192.168.175.1:9050'} );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 30, 137              │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 86                   │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
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
