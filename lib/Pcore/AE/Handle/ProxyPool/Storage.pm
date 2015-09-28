package Pcore::AE::Handle::ProxyPool::Storage;

use Pcore qw[-class];

has pool_id => ( is => 'ro', isa => Int, required => 1 );

has dbh => ( is => 'lazy', isa => Object, init_arg => undef );
has _connect_id => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

no Pcore;

sub _build_dbh ($self) {
    unlink 'proxy-pool.sqlite' or 1;    # TODO remove

    my $id = '__proxy_pool' . $self->pool_id;

    H->add(
        $id => 'SQLite',

        # TODO
        # addr => 'memory://',
        addr => 'file:./proxy-pool.sqlite',
    );

    my $dbh = H->$id;

    my $ddl = $dbh->ddl;

    $ddl->add_changeset(
        id  => 1,
        sql => <<'SQL'
            CREATE TABLE IF NOT EXISTS `proxy` (
                `id` INTEGER PRIMARY KEY NOT NULL,
                `hostport` TEXT NOT NULL,
                `source_id` INTEGER NOT NULL,
                `source_can_connect` INTEGER NOT NULL,
                `connect_error` INTEGER NOT NULL DEFAULT 0,
                `connect_error_time` INTEGER NOT NULL DEFAULT 0,
                `threads` INTEGER NOT NULL DEFAULT 0,
                `total_threads` INTEGER NOT NULL DEFAULT 0,
                `max_threads` INTEGER NOT NULL
            );

            CREATE UNIQUE INDEX IF NOT EXISTS `idx_proxy_hostport` ON `proxy` (`hostport` ASC);

            CREATE INDEX IF NOT EXISTS `idx_proxy_connect_error_time` ON `proxy` (`connect_error` DESC, `connect_error_time` ASC);

            CREATE TABLE IF NOT EXISTS `connect` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `name` TEXT NOT NULL
            );

            CREATE UNIQUE INDEX IF NOT EXISTS `idx_connect_name` ON `connect` (`name` ASC);

            CREATE TABLE IF NOT EXISTS `proxy_connect` (
                `proxy_id` INTEGER NOT NULL,
                `connect_id` INTEGER NOT NULL,
                `proxy_type` INTEGER NOT NULL,
                PRIMARY KEY (`proxy_id`, `connect_id`),
                FOREIGN KEY(`proxy_id`) REFERENCES `proxy`(`id`) ON DELETE CASCADE,
                FOREIGN KEY(`connect_id`) REFERENCES `connect`(`id`) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS `idx_proxy_connect_proxy_type` ON `proxy_connect` (`proxy_type` ASC);

            CREATE TABLE IF NOT EXISTS `proxy_ban` (
                `proxy_id` INTEGER NOT NULL,
                `key` INTEGER NOT NULL,
                `release_time` INTEGER NOT NULL,
                PRIMARY KEY (`proxy_id`, `key`),
                FOREIGN KEY(`proxy_id`) REFERENCES `proxy`(`id`) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS `idx_proxy_ban_release_time` ON `proxy_ban` (`release_time` ASC);
SQL
    );

    $ddl->upgrade;

    return $dbh;
}

# PROXY METHODS
sub add_proxy ( $self, $proxy ) {
    state $q1 = $self->dbh->query('INSERT INTO `proxy` (`id`, `hostport`, `source_id`, `source_can_connect`, `max_threads`) VALUES (?, ?, ?, ?, ?)');

    $q1->do( bind => [ $proxy->id, $proxy->hostport, $proxy->source->id, $proxy->source->can_connect, $proxy->max_threads ] );

    return;
}

sub remove_proxy ( $self, $proxy ) {
    state $q1 = $self->dbh->query('DELETE FROM `proxy` WHERE `id` = ?');

    $q1->do( bind => [ $proxy->id ] );

    return;
}

sub ban_proxy ( $self, $proxy, $key, $release_time ) {
    state $q2 = $self->dbh->query('INSERT OR REPLACE INTO `proxy_ban` (`proxy_id`, `key`, `release_time`) VALUES (?, ?, ?)');

    $q2->do( bind => [ $proxy->id, $key, $release_time ] );

    return;
}

sub set_connect_error ( $self, $proxy ) {
    state $q1 = $self->dbh->query('UPDATE `proxy` SET `connect_error` = 1, `connect_error_time` = ? WHERE `id` = ?');

    state $q2 = $self->dbh->query('DELETE FROM `proxy_connect` WHERE `proxy_id` = ?');

    $q1->do( bind => [ $proxy->{connect_error_time}, $proxy->id ] );

    $q2->do( bind => [ $proxy->id ] );

    return;
}

sub clear_connect_error ( $self, $proxy ) {
    state $q1 = $self->dbh->query('UPDATE `proxy` SET `connect_error` = 0 WHERE `id` = ?');

    $q1->do( bind => [ $proxy->id ] );

    return;
}

sub start_thread ( $self, $proxy ) {
    state $q1 = $self->dbh->query('UPDATE `proxy` SET `threads` = ?, `total_threads` = ? WHERE `id` = ?');

    # update threads in the DB
    $q1->do( bind => [ $proxy->{threads}, $proxy->{total_threads}, $proxy->id ] );

    return;
}

sub finish_thread ( $self, $proxy ) {
    state $q1 = $self->dbh->query('UPDATE `proxy` SET `threads` = ? WHERE `id` = ?');

    # update threads in the DB
    $q1->do( bind => [ $proxy->{threads}, $proxy->id ] );

    return;
}

sub set_test_connection ( $self, $proxy, $connect_id, $proxy_type ) {
    if ( !$self->_connect_id->{$connect_id} ) {
        state $q1 = $self->dbh->query('INSERT INTO `connect` (`name`) VALUES (?)');

        $q1->do( bind => [$connect_id] );

        $self->{_connect_id}->{$connect_id} = $self->dbh->last_insert_id;
    }

    state $q2 = $self->dbh->query('INSERT OR REPLACE INTO `proxy_connect` (`proxy_id`, `connect_id`, `proxy_type`) VALUES (?, ?, ?)');

    $q2->do( bind => [ $proxy->id, $self->{_connect_id}->{$connect_id}, $proxy_type ] );

    return;
}

# SOURCE METHODS
sub disable_source ( $self, $source ) {
    state $q1 = $self->dbh->query('UPDATE `proxy` SET `source_can_connect` = 0 WHERE `source_id` = ?');

    $q1->do( bind => [ $source->id ] );

    return;
}

sub enable_source ( $self, $source ) {
    state $q1 = $self->dbh->query('UPDATE `proxy` SET `source_can_connect` = 1 WHERE `source_id` = ?');

    $q1->do( bind => [ $source->id ] );

    return;
}

# MAINTENANCE METHODS
sub release_connect_error ( $self, $time ) {
    state $q1 = $self->dbh->query('UPDATE `proxy` SET `connect_error` = 0 WHERE `connect_error` = 1 AND `connect_error_time` <= ?');

    return $q1->do( bind => [$time] );
}

sub release_ban ( $self, $time ) {
    state $q1 = $self->dbh->query('DELETE FROM `proxy_ban` WHERE `release_time` <= ?');

    return $q1->do( bind => [$time] );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 146                  │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Handle::ProxyPool::Storage

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
