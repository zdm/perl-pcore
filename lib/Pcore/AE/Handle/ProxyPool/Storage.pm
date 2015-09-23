package Pcore::Proxy::Pool::Storage;

use Pcore qw[-class];

has dbh => ( is => 'lazy', init_arg => undef );

no Pcore;

our $CONNECT_ID = {};

sub _build_dbh ($self) {
    H->add(
        __proxy_pool => 'SQLite',

        addr => 'memory://',

        # addr => 'file:./proxy-pool.sqlite',
    );

    my $dbh = H->__proxy_pool;

    my $ddl = $dbh->ddl;

    $ddl->add_changeset(
        id  => 1,
        sql => <<'SQL'
            CREATE TABLE IF NOT EXISTS `proxy` (
                `id` TEXT PRIMARY KEY NOT NULL,
                `disabled` INTEGER NOT NULL DEFAULT 0,
                `threads` INTEGER NOT NULL DEFAULT 0
            );

            -- CREATE INDEX IF NOT EXISTS `idx_proxy_disabled` ON `proxy` (`disabled` DESC);

            -- CREATE INDEX IF NOT EXISTS `idx_proxy_threads` ON `proxy` (`threads` ASC);

            CREATE INDEX IF NOT EXISTS `idx_proxy_disabled_threads` ON `proxy` (`disabled` DESC, `threads` ASC);
SQL
    );

    $ddl->upgrade;

    return $dbh;
}

sub add_connect_id ( $self, $connect_id ) {
    return if exists $CONNECT_ID->{$connect_id};

    $CONNECT_ID->{connect_id} = 1;

    my $sql = <<"SQL";
        ALTER TABLE `proxy` ADD COLUMN `$connect_id`;

        CREATE INDEX IF NOT EXISTS `idx_proxy_$connect_id` ON `proxy` (`$connect_id` DESC);
SQL

    $self->dbh->do($sql);

    return;
}

sub add_proxy ( $self, $proxy ) {
    state $query = $self->dbh->query('INSERT OR IGNORE INTO `proxy` (`id`) VALUES (?)');

    $query->do( bind => [ $proxy->id ] );

    return;
}

sub remove_proxy ( $self, $proxy ) {
    state $query = $self->dbh->query('DELETE FROM `proxy` WHERE `id` = ?');

    $query->do( bind => [ $proxy->id ] );

    return;
}

sub disable_proxy ( $self, $proxy ) {
    state $query = $self->dbh->query('UPDATE `proxy` SET `disabled` = 1 WHERE `id` = ?');

    $query->do( bind => [ $proxy->id ] );

    return;
}

sub enable_proxy ( $self, $proxy ) {
    state $query = $self->dbh->query('UPDATE `proxy` SET `disabled` = 0 WHERE `id` = ?');

    $query->do( bind => [ $proxy->id ] );

    return;
}

sub select_proxy ( $self, $connect_id ) {
    state $cache = {};

    if ( !exists $cache->{$connect_id} ) {
        $self->add_connect_id($connect_id) if !exists $CONNECT_ID->{$connect_id};

        $cache->{$connect_id} = $self->dbh->query(qq[SELECT id FROM `proxy` WHERE disabled = 0 AND `$connect_id` <> 0 ORDER BY threads LIMIT 1]);
    }

    if ( my $res = $cache->{$connect_id}->selectrow ) {
        return $res;
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
## │    3 │ 20                   │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Proxy::Pool::Storage

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
