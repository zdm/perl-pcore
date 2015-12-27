package Pcore::API::Backend::Local::MySQL;

use Pcore -class;
use Pcore::Util::Text qw[to_camel_case];

with qw[Pcore::API::Backend::Local];

no Pcore;

sub run_ddl {
    my $self = shift;

    my $sql = q[
        CREATE TABLE IF NOT EXISTS `user` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `username` VARCHAR(32) NOT NULL,
            `digest` BINARY(23) NOT NULL,
            `disabled` TINYINT(1) NOT NULL DEFAULT 0,
            `created` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `data` BLOB NULL COMMENT 'additional user data, JSON',
            PRIMARY KEY (`id`),
            UNIQUE INDEX `user_username` (`username` ASC)
        ) ENGINE = InnoDB;

        CREATE TABLE IF NOT EXISTS `group` (
            `id` BIGINT UNSIGNED NOT NULL,
            `name` VARCHAR(45) NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE INDEX `group_name` (`name` ASC)
        ) ENGINE = InnoDB;

        CREATE TABLE IF NOT EXISTS `user_has_group` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `user_id` BIGINT UNSIGNED NOT NULL,
            `group_id` BIGINT UNSIGNED NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE INDEX `user_has_group_user_id_group_id` (`user_id`,`group_id`),
            INDEX `user_has_group_group_id` (`group_id` ASC),
            INDEX `group_id_user_id` (`user_id` ASC),
            CONSTRAINT `user_has_group_user`
                FOREIGN KEY (`user_id`)
                REFERENCES `user` (`id`)
                ON DELETE CASCADE
                ON UPDATE NO ACTION,
            CONSTRAINT `user_has_group_group`
                FOREIGN KEY (`group_id`)
                REFERENCES `group` (`id`)
                ON DELETE CASCADE
                ON UPDATE NO ACTION
        ) ENGINE = InnoDB;

        CREATE TABLE IF NOT EXISTS `api_app` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(45) NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE INDEX `api_app_name` (`name` ASC)
        ) ENGINE = InnoDB;

        CREATE TABLE IF NOT EXISTS `api_action` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(45) NOT NULL,
            `app` BIGINT UNSIGNED NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE INDEX `api_action_app_name` (`app` ASC, `name` ASC),
            CONSTRAINT `api_action_api_app`
                FOREIGN KEY (`app`)
                REFERENCES `api_app` (`id`)
                ON DELETE CASCADE
                ON UPDATE CASCADE
        ) ENGINE = InnoDB;

        CREATE TABLE IF NOT EXISTS `api_method` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(45) NOT NULL,
            `action` BIGINT UNSIGNED NOT NULL,
            `data` BLOB NOT NULL COMMENT 'JSON serialized additional method data',
            PRIMARY KEY (`id`),
            UNIQUE INDEX `api_method_action_name` (`action` ASC, `name` ASC),
            CONSTRAINT `api_method_api_action`
                FOREIGN KEY (`action`)
                REFERENCES `api_action` (`id`)
                ON DELETE CASCADE
                ON UPDATE CASCADE
        ) ENGINE = InnoDB;

        CREATE TABLE IF NOT EXISTS `api_session` (
            `id` BINARY(32) NOT NULL,
            `uid` BIGINT UNSIGNED NOT NULL,
            `last_accessed` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `api_session_uid` (`uid` ASC),
            INDEX `api_session_last_accessed` (`last_accessed` ASC),
            CONSTRAINT `api_session_user`
                FOREIGN KEY (`uid`)
                REFERENCES `user` (`id`)
                ON DELETE CASCADE
                ON UPDATE CASCADE
        ) ENGINE = InnoDB;

        CREATE TABLE IF NOT EXISTS `api_information` (
            `id` BIGINT UNSIGNED NOT NULL DEFAULT 1,
            `sessions_last_cleaned` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE = InnoDB;
    ];

    $self->h_api->ddl( { ddl => $sql, id => 'api', sql_mode => [qw[TRADITIONAL ALLOW_INVALID_DATES]] } )->run;

    # automatically create root user
    unless ( $self->h_api->selectval(q[SELECT `id` FROM `user` WHERE `id` = 1]) ) {
        print 'Enter root password:';
        my $password = <>;
        chomp $password;

        my $digest = $self->hash_password( 'root', $password );

        $self->h_api->do( q[INSERT INTO `user` SET `id` = 1, `username` = 'root', `digest` = ?], bind => [$digest] );
    }

    return;
}

# API
sub sync_api_map {
    my $self    = shift;
    my $api_map = shift;

    $self->h_api->begin_work;

    # create app
    $self->h_api->do( 'INSERT IGNORE INTO `api_app` SET `name` = ?', bind => [ $self->app->name ] );

    my $app_id = $self->h_api->selectval( 'SELECT `id` FROM `api_app` WHERE name = ?', bind => [ $self->app->name ] ) // die;

    my $old_actions = {};
    my $old_methods = {};

    # fetch old api structure
    if ( my $old_api = $self->h_api->selectall( 'SELECT `api_action`.`name` AS `action_name`, `api_method`.`action`, `api_method`.`id`, `api_method`.`name` FROM `api_action`, `api_method` WHERE `api_method`.`action` = `api_action`.`id` AND `api_action`.`app` = ?', bind => [ $app_id->$* ] ) ) {
        for my $method ( $old_api->@* ) {
            $old_actions->{ $method->{action} } = 1;

            $old_methods->{ $method->{action_name} . q[#] . $method->{name} } = $method->{id};
        }
    }

    for my $action ( keys $api_map->%* ) {

        # create action
        $self->h_api->do( 'INSERT IGNORE INTO `api_action` SET `name` = ?, `app` = ?', bind => [ $action, $app_id->$* ] );
        my $action_id = $self->h_api->selectval( 'SELECT `id` FROM `api_action` WHERE name = ?', bind => [$action] ) // die;

        delete $old_actions->{ $action_id->$* };

        for my $method ( keys $api_map->{$action}->%* ) {
            my $data = P->data->encode( $api_map->{$action}->{$method} );

            $self->h_api->do( 'INSERT INTO `api_method` SET `name` = ?, action = ?, data = ? ON DUPLICATE KEY UPDATE data = ?', bind => [ $method, $action_id->$*, $data->$*, $data->$* ] );

            delete $old_methods->{ $action . q[#] . $method };
        }
    }

    # delete old actions without methods
    for my $old_action_id ( keys $old_actions->%* ) {
        $self->h_api->do( 'DELETE FROM api_action WHERE id = ?', bind => [$old_action_id] );
    }

    # delete old methods
    for my $old_method_id ( values $old_methods->%* ) {
        $self->h_api->do( 'DELETE FROM api_method WHERE id = ?', bind => [$old_method_id] );
    }

    $self->h_api->commit;

    return;
}

sub _build_api_map {
    my $self = shift;

    my $api_map = {};

    if ( my $res = $self->h_api->selectall( 'SELECT `api_action`.`name` AS `action_name`, `api_method`.* FROM `api_app`, `api_action`, `api_method` WHERE `api_method`.`action` = `api_action`.`id` AND `api_action`.`app` = `api_app`.`id` AND `api_app`.`name` = ?', bind => [ $self->app->name ] ) ) {
        for my $row ( $res->@* ) {
            $api_map->{ $row->{action_name} } //= {
                id      => $row->{action},
                class   => to_camel_case( $row->{action_name}, ucfirst => 1, split => q[.], join => q[::] ),
                methods => {},
            };

            my $method = P->data->decode( delete $row->{data} );

            $method->{id} = $row->{id};

            $api_map->{ $row->{action_name} }->{methods}->{ $row->{name} } = $method;
        }
    }

    return $api_map;
}

# AUTH
sub do_signout {
    my $self = shift;

    return unless $self->has_sid;

    $self->h_api->do( q[DELETE FROM api_session WHERE id = ?], bind => [ pack 'H*', $self->sid ] );

    return;
}

sub find_user {
    my $self = shift;
    my %args = (
        token    => undef,    # token as hex string
        sid      => undef,    # sid as hex string
        username => undef,
        @_,
    );

    if ( $args{token} ) {
        return $self->h_api->selectrow_hashref( q[SELECT id AS uid FROM user WHERE disabled = 0 AND token = ?], bind => [ pack 'H*', $args{token} ] );
    }
    elsif ( $args{sid} ) {
        my $sid = pack 'H*', $args{sid};

        if ( my $res = $self->h_api->selectrow_hashref( q[SELECT uid FROM api_session WHERE id = ? AND UNIX_TIMESTAMP(last_accessed) >= ?], bind => [ $sid, time - $self->session_ttl ] ) ) {
            $self->h_api->do( q[UPDATE api_session SET last_accessed = CURRENT_TIMESTAMP WHERE id = ?], bind => [$sid] );

            return $res;
        }
        else {
            return;
        }
    }
    elsif ( $args{username} ) {
        return $self->h_api->selectrow_hashref( q[SELECT id AS uid, digest FROM user WHERE disabled = 0 AND username = ?], bind => [ $args{username} ] );
    }
}

sub create_sid {    # return newly created sid as hex string
    my $self = shift;
    my $uid  = shift;

    my $sid;

    while (1) {
        $sid = $self->generate_sid;

        last if $self->h_api->do( q[INSERT INTO api_session SET id = ?, uid = ?, last_accessed = CURRENT_TIMESTAMP], bind => [ pack( 'H*', $sid ), $uid ] );
    }

    return $sid;
}

sub cleanup_expired_sessions {
    my $self = shift;

    my $sessions_last_cleaned = $self->h_api->selectval(q[SELECT UNIX_TIMESTAMP(sessions_last_cleaned) FROM api_information WHERE id = 1]);

    if ( !$sessions_last_cleaned || $sessions_last_cleaned->$* < ( time - $self->sessions_cleanup_timeout ) ) {
        $self->h_api->do(q[INSERT INTO api_information SET id = 1, sessions_last_cleaned = NOW() ON DUPLICATE KEY UPDATE sessions_last_cleaned = NOW()]);

        $self->h_api->do( q[DELETE FROM api_session WHERE UNIX_TIMESTAMP(last_accessed) < ?], bind => [ time - $self->session_ttl ] );
    }

    return;
}

# TODO this method used to authorize particular API call
sub auth_method {
    my $self = shift;
    my $id   = shift;

    # TODO check authenticateion

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 12                   │ ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 146, 154, 164, 169   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
