package Pcore::AE::Handle::ProxyPool;

use Pcore qw[-class];

has load_timeout => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );    # 0 - don't re-load proxy sources
has _load_timer => ( is => 'ro', init_arg => undef );

has check_timeout => ( is => 'ro', isa => PositiveInt, default => 180 );        # timeout for re-check disabled proxies
has check_failure => ( is => 'ro', isa => PositiveInt, default => 3 );          # max. failed check attempts, after proxy will be removed from pool
has _check_timer => ( is => 'ro', init_arg => undef );

has ban_timeout => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );     # 0 - don't ban proxies

has _source => ( is => 'ro', isa => ArrayRef [ ConsumerOf ['Pcore::AE::Handle::ProxyPool::Source'] ], default => sub { [] }, init_arg => undef );

has _on_proxy_activated => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

has dbh => ( is => 'lazy', isa => Object, init_arg => undef );
has list => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

no Pcore;

sub BUILD ( $self, $args ) {
    if ( $args->{source} ) {
        my $min_source_load_timeout = 0;

        for my $source_args ( $args->{source}->@* ) {
            my %args = $source_args->%*;

            $args{pool} = $self;

            my $source = P->class->load( delete $args{class}, ns => 'Pcore::AE::Handle::ProxyPool::Source' )->new( \%args );

            # set source load timeout = pool load timeout, if source timeout is not defined
            $source->{load_timeout} = $self->load_timeout if !defined $source->load_timeout;

            # define minimal source load interval, if source is reloadable
            if ( $source->load_timeout ) {
                if ( !$min_source_load_timeout ) {
                    $min_source_load_timeout = $source->load_timeout;
                }
                elsif ( $source->load_timeout < $min_source_load_timeout ) {
                    $min_source_load_timeout = $source->load_timeout;
                }
            }

            # add source to the pool
            push $self->_source, $source;
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
    # $self->{_check_timer} = AE::timer $self->check_timeout, $self->check_timeout, sub {
    #     $self->_on_check_timer;
    #
    #     return;
    # };

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
                `disabled` INTEGER NOT NULL DEFAULT 0,
                `disabled_ts` INTEGER NOT NULL DEFAULT 0,
                `threads` INTEGER NOT NULL DEFAULT 0
            );

            CREATE UNIQUE INDEX IF NOT EXISTS `idx_proxy_id` ON `proxy` (`id` ASC);

            -- CREATE INDEX IF NOT EXISTS `idx_proxy_disabled` ON `proxy` (`disabled` DESC);

            -- CREATE INDEX IF NOT EXISTS `idx_proxy_threads` ON `proxy` (`threads` ASC);

            CREATE INDEX IF NOT EXISTS `idx_proxy_disabled_threads` ON `proxy` (`disabled` DESC, `threads` ASC);
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

sub _on_check_timer ($self) {
    for my $source ( $self->_source->@* ) {
        $source->on_check_timer;
    }

    return;
}

sub add_proxy ( $self, $proxy ) {
    return if exists $self->list->{ $proxy->id };

    state $q1 = $self->dbh->query('INSERT INTO `proxy` (`id`, `source_id`) VALUES (?, ?)');

    $q1->do( bind => [ $proxy->id, $proxy->source->id ] );

    $proxy->{pool_id} = $self->dbh->last_insert_id;

    $self->list->{ $proxy->id } = $proxy;

    return;
}

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
## │    3 │ 28                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 87                   │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 126                  │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_on_check_timer' declared but not   │
## │      │                      │ used                                                                                                           │
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
