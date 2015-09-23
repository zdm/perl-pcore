package Pcore::AE::Handle::ProxyPool;

use Pcore qw[-class];

has load_timeout          => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );     # 0 - don't re-load proxy sources
has connect_error_timeout => ( is => 'ro', isa => PositiveInt,       default => 180 );    # timeout for re-check disabled proxies
has max_connect_errors    => ( is => 'ro', isa => PositiveInt,       default => 3 );      # max. failed check attempts, after proxy will be removed
has ban_timeout           => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );
has max_threads_proxy     => ( is => 'ro', isa => PositiveOrZeroInt, default => 20 );
has max_threads_source    => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );
has maintanance_timeout   => ( is => 'ro', isa => PositiveInt,       default => 60 );

has _source => ( is => 'ro', isa => ArrayRef [ ConsumerOf ['Pcore::AE::Handle::ProxyPool::Source'] ], default => sub { [] }, init_arg => undef );
has _timer      => ( is => 'ro',   init_arg => undef );
has _connect_id => ( is => 'lazy', init_arg => undef );

has dbh => ( is => 'lazy', isa => Object, init_arg => undef );
has list => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

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
                `max_threads` INTEGER NOT NULL,
                `http_80` INTEGER NOT NULL DEFAULT -1,       -- -1 = not tested, 0 = not avail. 1 = ok
                `https_443` INTEGER NOT NULL DEFAULT -1,     -- -1 = not tested, 0 = not avail. 1 = ok
                `whois_43` INTEGER NOT NULL DEFAULT -1       -- -1 = not tested, 0 = not avail. 1 = ok
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

sub _build__connect_id ($self) {
    return {
        http_80   => 1,
        https_443 => 1,
        whois_43  => 1,
    };
}

# TODO throw event, some proxies was enabled
# TODO release banned proxies
sub _maintenance ($self) {

    # load sources
    for my $source ( $self->_source->@* ) {
        $source->load;
    }

    # drop connection errors
    state $q1 = $self->dbh->query('UPDATE `proxy` SET `connect_error` = 0 WHERE `connect_error` = 1 AND `connect_error_time` <= ?');

    my $time = time;

    if ( $q1->do( bind => [$time] ) ) {

        # TODO throw proxy avail event

        for my $proxy ( values $self->list->%* ) {
            $proxy->{connect_error} = 0 if $proxy->{connect_error} && $proxy->{connect_error_time} <= $time;
        }
    }

    # TODO release bans

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

sub _add_connect_id ( $self, $connect_id ) {
    return if exists $self->_connect_id->{$connect_id};

    $self->{_connect_id}->{$connect_id} = 1;

    my $sql = <<"SQL";
        ALTER TABLE `proxy` ADD COLUMN `$connect_id` INTEGER NOT NULL DEFAULT -1; -- -1 = not tested, 0 = not avail. 1 = ok

        CREATE INDEX IF NOT EXISTS `idx_proxy_$connect_id` ON `proxy` (`$connect_id` DESC);
SQL

    $self->dbh->do($sql);

    return;
}

# TODO
sub get_proxy ( $self, $connect, @ ) {
    my $cb = $_[-1];

    my %args = (
        ban => 0,
        @_[ 2 .. $#_ - 1 ],
    );

    state $cache = {};

    $connect->[2] //= 'tcp';

    $connect->[3] //= $connect->[2] . q[_] . $connect->[1];

    $self->_add_connect_id( $connect->[3] );

    $cache->{ $connect->[3] } //= $self->dbh->query(
        <<"SQL"
            SELECT `id`
            FROM `proxy`
            WHERE
                `connect_error` = 0
                AND `source_can_connect` = 1
                AND `$connect->[3]` <> 0
                AND `threads` < `max_threads`
            ORDER BY `threads` ASC
            LIMIT 1
SQL
    );

    if ( my $res = $cache->{ $connect->[3] }->selectval ) {
        $cb->( $self->list->{ $res->$* } );
    }
    else {
        $cb->();
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
## │    3 │ 25, 122              │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 58                   │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
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
