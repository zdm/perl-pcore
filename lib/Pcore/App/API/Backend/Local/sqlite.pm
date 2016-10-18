package Pcore::App::API::Backend::Local::sqlite;

use Pcore -class;
use Pcore::Util::Response qw[status];

with qw[Pcore::App::API::Backend::Local];

# INIT DB
sub init_db ( $self, $cb ) {

    # create db
    my $ddl = $self->dbh->ddl;

    $ddl->add_changeset(
        id  => 1,
        sql => <<"SQL"

            --- APP
            CREATE TABLE IF NOT EXISTS `api_app` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `name` BLOB NOT NULL UNIQUE,
                `desc` TEXT NOT NULL,
                `created_ts` INTEGER,
                `enabled` INTEGER NOT NULL DEFAULT 0
            );

            --- APP INSTANCE
            CREATE TABLE IF NOT EXISTS `api_app_instance` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `app_id` NOT NULL REFERENCES `api_app` (`id`) ON DELETE RESTRICT,
                `version` BLOB NOT NULL,
                `host` BLOB NOT NULL,
                `created_ts` INTEGER,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `last_connected_ts` INTEGER,
                `hash` BLOB
            );

            --- APP ROLE
            CREATE TABLE IF NOT EXISTS `api_app_role` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `app_id` INTEGER NOT NULL REFERENCES `api_app` (`id`) ON DELETE CASCADE,
                `name` BLOB NOT NULL,
                `desc` TEXT NOT NULL,
                `enabled` INTEGER NOT NULL DEFAULT 0
            );

            CREATE UNIQUE INDEX `idx_uniq_api_app_role_app_id_name` ON `api_app_role` (`app_id`, `name`);

            --- APP PERMISSIONS
            CREATE TABLE IF NOT EXISTS `api_app_permissions` (
                `app_id` INTEGER NOT NULL REFERENCES `api_app` (`id`) ON DELETE CASCADE, --- remove role assoc., on app delete
                `role_id` INTEGER NOT NULL REFERENCES `api_app_role` (`id`) ON DELETE RESTRICT, --- prevent deleting role, if has assigned apps
                `enabled` INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (`app_id`, `role_id`)
            );

            --- USER
            CREATE TABLE IF NOT EXISTS `api_user` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `name` TEXT NOT NULL UNIQUE,
                `created_ts` INTEGER,
                `hash` BLOB,
                `enabled` INTEGER NOT NULL DEFAULT 0
            );

            --- USER PERMISSIONS
            CREATE TABLE IF NOT EXISTS `api_user_permissions` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `user_id` INTEGER NOT NULL REFERENCES `api_user` (`id`) ON DELETE CASCADE, --- remove role assoc., on user delete
                `role_id` INTEGER NOT NULL REFERENCES `api_app_role` (`id`) ON DELETE RESTRICT, --- prevent deleting role, if has assigned users
                `enabled` INTEGER NOT NULL DEFAULT 0
            );

            CREATE UNIQUE INDEX `idx_uniq_api_user_permissions` ON `api_user_permissions` (`user_id`, `role_id`);

            --- USER TOKEN
            CREATE TABLE IF NOT EXISTS `api_user_token` (
                `id` BLOB PRIMARY KEY NOT NULL, --- UUID hex
                `user_id` INTEGER NOT NULL REFERENCES `api_user` (`id`) ON DELETE CASCADE,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `desc` TEXT,
                `created_ts` INTEGER,
                `hash` BLOB UNIQUE
            );

            --- USER TOKEN PERMISSIONS
            CREATE TABLE IF NOT EXISTS `api_user_token_permissions` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `user_token_id` BLOB NOT NULL REFERENCES `api_user_token` (`id`) ON DELETE CASCADE,
                `user_permissions_id` INTEGER NOT NULL REFERENCES `api_user_permissions` (`id`) ON DELETE CASCADE
            );

            CREATE UNIQUE INDEX `idx_uniq_api_user_token_permissions` ON `api_user_token_permissions` (`user_token_id`, `user_permissions_id`);

            --- USER SESSION
            CREATE TABLE IF NOT EXISTS `api_user_session` (
                `id` BLOB PRIMARY KEY NOT NULL, --- UUID hex
                `user_id` INTEGER NOT NULL REFERENCES `api_user` (`id`) ON DELETE CASCADE,
                `created_ts` INTEGER,
                `user_agent` TEXT NOT NULL,
                `remote_ip` BLOB NOT NULL,
                `remote_ip_geo` BLOB NOT NULL,
                `hash` BLOB UNIQUE
            );
SQL
    );

    $ddl->upgrade;

    $cb->( status 200 );

    return;
}

# REGISTER APP INSTANCE
sub register_app_instance ( $self, $app_name, $app_desc, $app_permissions, $app_instance_host, $app_instance_version, $cb ) {
    $self->get_app(
        $app_name,
        sub ( $res ) {
            my $dbh = $self->dbh;

            $dbh->begin_work;

            my $app_id;

            # app exists
            if ($res) {

                # app is disabled, registration is disallowed
                if ( !$res->{app}->{enabled} ) {
                    $dbh->rollback;

                    $cb->( status [ 400, 'App is disabled' ] );

                    return;
                }

                $app_id = $res->{app}->{id};
            }

            # app is not exists, create app
            else {

                # app creation error
                if ( !$dbh->do( q[INSERT OR IGNORE INTO api_app (name, desc, enabled, created_ts) VALUES (?, ?, 0, ?)], [ $app_name, $app_desc, time ] ) ) {
                    $dbh->rollback;

                    $cb->( status [ 500, 'Error creation app' ] );

                    return;
                }

                # get app id
                $app_id = $dbh->last_insert_id;
            }

            # add app permissions;
            $self->_add_app_permissions(
                $dbh, $app_id,
                $app_permissions,
                sub ($status) {

                    # error creation app permissions
                    if ( !$status && $status != 304 ) {
                        $dbh->rollback;

                        $cb->($status);

                        return;
                    }

                    # create disabled app instance
                    if ( !$dbh->do( q[INSERT OR IGNORE INTO api_app_instance (app_id, host, version, enabled, created_ts) VALUES (?, ?, ?, 0, ?)], [ $app_id, $app_instance_host, $app_instance_version, time ] ) ) {

                        # app instance creation error
                        $dbh->rollback;

                        $cb->( status [ 500, 'App instance creation error' ] );

                        return;
                    }

                    my $app_instance_id = $dbh->last_insert_id;

                    # set app instance token
                    $self->_generate_app_instance_token(
                        $app_instance_id,
                        sub ( $res ) {

                            # app instance token generation error
                            if ( !$res ) {
                                $dbh->rollback;

                                $cb->($res);

                                return;
                            }

                            # store app instance token
                            if ( !$dbh->do( q[UPDATE api_app_instance SET hash = ? WHERE id = ?], [ $res->{hash}, $app_instance_id ] ) ) {
                                $dbh->rollback;

                                $cb->( status [ 500, 'Error creation app instance token' ] );

                                return;
                            }

                            # registration process finished successfully
                            $dbh->commit;

                            $cb->( status 201, app_instance_id => $app_instance_id, app_instance_token => $res->{token} );

                            return;
                        }
                    );

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub _connect_app_instance ( $self, $local, $app_instance_id, $app_instance_version, $app_roles, $app_permissions, $cb ) {
    $self->get_app_instance(
        $app_instance_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $app_instance = $res->{app_instance};

            # update add instance
            if ( !$self->dbh->do( q[UPDATE OR IGNORE api_app_instance SET version = ?, last_connected_ts = ? WHERE id = ?], [ $app_instance_version, time, $app_instance_id ] ) ) {
                $cb->( status [ 500, 'Update app instance error' ] );

                return;
            }

            # add app permissions;
            $self->_add_app_permissions(
                $self->dbh,
                $app_instance->{app_id},
                $app_permissions,
                sub ($status) {

                    # error adding permissions
                    if ( !$status && $status != 304 ) {
                        $cb->($status);

                        return;
                    }

                    if ($local) {
                        $self->_connect_local_app_instance(
                            $app_instance->{app_id},
                            $app_instance_id,
                            sub ($status) {
                                if ( !$status ) {
                                    $cb->($status);

                                    return;
                                }

                                $self->_connect_app_instance1( $app_instance->{app_id}, $app_roles, $cb );

                                return;
                            }
                        );
                    }
                    else {
                        $self->_connect_app_instance1( $app_instance->{app_id}, $app_roles, $cb );
                    }

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub _connect_app_instance1 ( $self, $app_id, $app_roles, $cb ) {

    # check, that all app permissions are enabled
    if ( my $permissions = $self->dbh->selectall( q[SELECT enabled FROM api_app WHERE id = ?], [$app_id] ) ) {
        for ( $permissions->@* ) {
            if ( !$_->{enabled} ) {
                $cb->( status [ 400, 'App permisisons are disabled' ] );

                return;
            }
        }
    }

    # add app roles
    $self->_add_app_roles(
        $app_id,
        $app_roles,
        sub ($status) {
            if ( !$status && $status != 304 ) {
                $cb->($status);

                return;
            }

            # app instance connected
            $cb->( status 200 );

            return;
        }
    );

    return;
}

sub _connect_local_app_instance ( $self, $app_id, $app_instance_id, $cb ) {

    # enabled app
    $self->dbh->do( q[UPDATE api_app SET enabled = 1 WHERE id = ?], [$app_id] );

    # enabled app instance
    $self->dbh->do( q[UPDATE api_app_instance SET enabled = 1 WHERE id = ?], [$app_instance_id] );

    # enabled all app permissions
    $self->dbh->do( q[UPDATE api_app_permissions SET enabled = 1 WHERE app_id = ?], [$app_id] );

    # create root user
    $self->_create_root_user(
        sub ( $res ) {
            if ( !$res && $res != 304 ) {
                $cb->($res);

                return;
            }

            if ( $res->{password} ) {
                say "Root user created: root / $res->{password}";
            }

            $self->{app}->{api}->connect_local_app_instance(
                sub ($res) {
                    $cb->($res);

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub _add_app_permissions ( $self, $dbh, $app_id, $permissions, $cb ) {
    my ( $error, $modified );

    my $cv = AE::cv sub {
        if ($error) { $cb->( status [ 400, join q[, ], $error->@* ] ) }
        elsif ( !$modified ) { $cb->( status 304 ) }
        else                 { $cb->( status 201 ) }

        return;
    };

    $cv->begin;

    if ( !$permissions ) {
        $cv->end;

        return;
    }

    for my $permission ( $permissions->@* ) {
        $cv->begin;

        $self->get_app_role(
            $permission,
            sub ( $res ) {
                if ( !$res ) {
                    push $error->@*, $permission;
                }
                else {
                    my $role = $res->{role};

                    # permission is not exists
                    if ( !$dbh->selectrow( q[SELECT FROM api_app_permission WHERE app_id = ? AND role_id = ?], [ $app_id, $role->{id} ] ) ) {

                        # create new disabled app permisison record
                        if ( $dbh->do( q[INSERT OR IGNORE INTO api_app_permissions (app_id, role_id, enabled) VALUES (?, ?, 0)], [ $app_id, $role->{id} ] ) ) {
                            $modified = 1;
                        }
                        else {
                            push $error->@*, $permission;
                        }
                    }
                }

                $cv->end;

                return;
            }
        );
    }

    $cv->end;

    return;
}

sub _add_app_roles ( $self, $app_id, $app_roles, $cb ) {
    my ( $error, $modified );

    my $cv = AE::cv sub {
        if    ($error)       { $cb->( status 500 ) }
        elsif ( !$modified ) { $cb->( status 304 ) }
        else                 { $cb->( status 201 ) }

        return;
    };

    $cv->begin;

    for my $role_name ( keys $app_roles->%* ) {
        if ( $self->dbh->do( q[INSERT OR IGNORE INTO api_app_role (app_id, name, desc, enabled) VALUES (?, ?, ?, 1)], [ $app_id, $role_name, $app_roles->{$role_name} ] ) ) {
            $modified = 1;
        }
    }

    $cv->end;

    return;
}

sub _create_root_user ( $self, $cb ) {
    $self->get_user(
        1,
        sub ( $res ) {

            # user_id 1 already exists
            if ( $res != 404 ) {
                $cb->( status 304 );

                return;
            }

            my $user = $res->{user};

            # generate random root password
            my $root_password = P->data->to_b64_url( P->random->bytes(32) );

            # generate root password hash
            $self->_generate_user_password_hash(
                'root',
                $root_password,
                sub ( $res ) {
                    if ( !$res ) {
                        $cb->($res);

                        return;
                    }

                    if ( $self->dbh->do( q[INSERT OR IGNORE INTO api_user (id, name, hash, enabled, created_ts) VALUES (1, ?, ?, 1, ?)], [ 'root', $res->{hash}, time ] ) ) {
                        $cb->( status 200, password => $root_password );
                    }
                    else {
                        $cb->( status [ 500, 'Error creating root user' ] );
                    }

                    return;
                }
            );

            return;
        }
    );

    return;
}

# AUTH
sub _auth_user_password ( $self, $source_app_instance_id, $user_name_utf8, $private_token, $cb ) {
    state $sql1 = <<'SQL';
        SELECT
            id,
            hash,
            enabled
        FROM
            api_user
        WHERE
            name = ?
SQL

    state $sql2 = <<'SQL';
        SELECT
            api_app_role.name AS source_app_role_name
        FROM
            api_app_instance,
            api_app_role,
            api_user_permissions
        WHERE
            api_app_instance.id = ?                                                      --- source app_instance_id
            AND api_app_role.app_id = api_app_instance.app_id                            --- link source_app_instance_role to source_app
            AND api_app_role.enabled = 1                                                 --- source_app_role must be enabled

            AND api_app_role.id = api_user_permissions.role_id                           --- link app_role to user_permissions
            AND api_user_permissions.enabled = 1                                         --- user permission must be enabled
            AND api_user_permissions.user_id = ?
SQL

    # get user
    my $res = $self->dbh->selectrow( $sql1, [$user_name_utf8] );

    # user not found
    if ( !$res ) {
        $cb->( status [ 404, 'User not found' ] );

        return;
    }

    my $continue = sub {
        my $user_id = $res->{id};

        my $auth = {
            user_id   => $user_id,
            user_name => $user_name_utf8,
            enabled   => $res->{enabled},
        };

        my $tags = {    #
            user_id => $user_id,
        };

        # get permissions
        if ( my $roles = $self->dbh->selectall( $sql2, [ $source_app_instance_id, $user_id ] ) ) {
            for my $row ( $roles->@* ) {
                $auth->{permissions}->{ $row->{source_app_role_name} } = 1;
            }
        }
        else {
            $auth->{permissions} = {};
        }

        $cb->( status 200, auth => $auth, tags => $tags );

        return;
    };

    if ($private_token) {

        # verify token
        $self->_verify_token_hash(
            $private_token,
            $res->{hash},
            sub ($status) {

                # token valid
                if ($status) {
                    $continue->();
                }

                # token is invalid
                else {
                    $cb->($status);
                }

                return;
            }
        );
    }
    else {
        $continue->();
    }

    return;
}

sub _auth_app_instance_token ( $self, $source_app_instance_id, $app_instance_id, $private_token, $cb ) {
    state $sql1 = <<'SQL';
        SELECT
            api_app_instance.app_id,
            api_app_instance.hash,
            api_app.enabled AS app_enabled,
            api_app_instance.enabled AS app_instance_enabled
        FROM
            api_app,
            api_app_instance
        WHERE
            api_app_instance.app_id = api_app.id
            AND api_app_instance.id = ?
SQL

    state $sql2 = <<'SQL';
        SELECT
            api_app_role.name AS source_app_role_name
        FROM
            api_app_instance,
            api_app_role,
            api_app_permissions
        WHERE
            api_app_instance.id = ?                              --- source app_instance_id
            AND api_app_role.app_id = api_app_instance.app_id    --- link source_app_instance_role to source_app
            AND api_app_role.enabled = 1                         --- source_app_role must be enabled

            AND api_app_permissions.role_id = api_app_role.id    --- link permission to role
            AND api_app_permissions.enabled = 1                  --- permission must be enabled
            AND api_app_permissions.app_id = ?                   --- link permission to target app id
SQL

    # get app instance
    my $res = $self->dbh->selectrow( $sql1, [$app_instance_id] );

    # app instance not found
    if ( !$res ) {
        $cb->( status [ 404, 'App instance not found' ] );

        return;
    }

    my $continue = sub {
        my $app_id = $res->{app_id};

        my $auth = {
            app_id          => $app_id,
            app_instance_id => $app_instance_id,
            enabled         => $res->{app_enabled} && $res->{app_instance_enabled},
        };

        my $tags = {
            app_id          => $res->{app_id},
            app_instance_id => $app_instance_id,
        };

        # get permissions
        if ( my $roles = $self->dbh->selectall( $sql2, [ $source_app_instance_id, $app_id ] ) ) {
            for my $row ( $roles->@* ) {
                $auth->{permissions}->{ $row->{source_app_role_name} } = 1;
            }
        }
        else {
            $auth->{permissions} = {};
        }

        $cb->( status 200, auth => $auth, tags => $tags );

        return;
    };

    if ($private_token) {

        # verify token
        $self->_verify_token_hash(
            $private_token,
            $res->{hash},
            sub ($status) {

                # token valid
                if ($status) {
                    $continue->();
                }

                # token is invalid
                else {
                    $cb->($status);
                }

                return;
            }
        );
    }
    else {
        $continue->();
    }

    return;
}

sub _auth_user_token ( $self, $source_app_instance_id, $user_token_id, $private_token, $cb ) {
    state $sql1 = <<'SQL';
        SELECT
            api_user.id AS user_id,
            api_user.name AS user_name,
            api_user.enabled AS user_enabled,
            api_user_token.hash,
            api_user_token.enabled AS user_token_enabled
        FROM
            api_user,
            api_user_token
        WHERE
            api_user_token.id = ?
            AND api_user_token.user_id = api_user.id
SQL

    state $sql2 = <<'SQL';
        SELECT
            api_app_role.name AS source_app_role_name
        FROM
            api_app_instance,
            api_app_role,
            api_user_permissions,
            api_user_token_permissions
        WHERE
            api_app_instance.id = ?                                                         --- source app_instance_id
            AND api_app_role.app_id = api_app_instance.app_id                               --- link source_app_instance_role to source_app
            AND api_app_role.enabled = 1                                                    --- source_app_role must be enabled

            AND api_app_role.id = api_user_permissions.role_id                              --- link app_role to user_permissions
            AND api_user_permissions.enabled = 1                                            --- user permission must be enabled

            AND api_user_permissions.id = api_user_token_permissions.user_permissions_id    --- link user_token_permissions to user_permissions
            AND api_user_token_permissions.user_token_id = ?                                --- link user_token_permissions to user_token
SQL

    # get user token by token id
    my $res = $self->dbh->selectrow( $sql1, [$user_token_id] );

    # user token not found
    if ( !$res ) {
        $cb->( status [ 404, 'User token not found' ] );

        return;
    }

    my $user_id = $res->{user_id};

    my $continue = sub {
        my $auth = {
            user_id       => $user_id,
            user_name     => $res->{user_name},
            user_token_id => $user_token_id,
            enabled       => $res->{user_enabled} && $res->{user_token_enabled},
        };

        my $tags = {
            user_id       => $user_id,
            user_token_id => $user_token_id,
        };

        # get permissions
        if ( my $roles = $self->dbh->selectall( $sql2, [ $source_app_instance_id, $user_token_id ] ) ) {
            for my $row ( $roles->@* ) {
                $auth->{permissions}->{ $row->{source_app_role_name} } = 1;
            }
        }
        else {
            $auth->{permissions} = {};
        }

        $cb->( status 200, auth => $auth, tags => $tags );

        return;
    };

    if ($private_token) {

        # verify token
        $self->_verify_token_hash(
            $private_token . $user_id,
            $res->{hash},
            sub ($status) {

                # token valid
                if ($status) {
                    $continue->();
                }

                # token is invalid
                else {
                    $cb->($status);
                }

                return;
            }
        );
    }
    else {
        $continue->();
    }

    return;
}

# TODO
sub _auth_user_session ( $self, $source_app_instance_id, $user_token_id, $private_token, $cb ) {
    state $sql1 = <<'SQL';
        SELECT
            api_user.id AS user_id,
            api_user.name AS user_name,
            api_user.enabled AS user_enabled,
            api_user_token.hash,
            api_user_token.enabled AS user_token_enabled
        FROM
            api_user,
            api_user_token
        WHERE
            api_user_token.id = ?
            AND api_user_token.user_id = api_user.id
SQL

    state $sql2 = <<'SQL';
        SELECT
            api_app_role.name AS source_app_role_name
        FROM
            api_app_instance,
            api_app_role,
            api_user_permissions,
            api_user_token_permissions
        WHERE
            api_app_instance.id = ?                                                         --- source app_instance_id
            AND api_app_role.app_id = api_app_instance.app_id                               --- link source_app_instance_role to source_app
            AND api_app_role.enabled = 1                                                    --- source_app_role must be enabled

            AND api_app_role.id = api_user_permissions.role_id                              --- link app_role to user_permissions
            AND api_user_permissions.enabled = 1                                            --- user permission must be enabled

            AND api_user_permissions.id = api_user_token_permissions.user_permissions_id    --- link user_token_permissions to user_permissions
            AND api_user_token_permissions.user_token_id = ?                                --- link user_token_permissions to user_token
SQL

    # get user token instance
    my $res = $self->dbh->selectrow( $sql1, [$user_token_id] );

    # user token not found
    if ( !$res ) {
        $cb->( status [ 404, 'User token not found' ] );

        return;
    }

    my $continue = sub {
        my $user_id = $res->{user_id};

        my $auth = {
            user_id       => $user_id,
            user_name     => $res->{user_name},
            user_token_id => $user_token_id,
            enabled       => $res->{user_enabled} && $res->{user_token_enabled},
        };

        my $tags = {
            user_id       => $user_id,
            user_token_id => $user_token_id,
        };

        # get permissions
        if ( my $roles = $self->dbh->selectall( $sql2, [ $source_app_instance_id, $user_token_id ] ) ) {
            for my $row ( $roles->@* ) {
                $auth->{permissions}->{ $row->{source_app_role_name} } = 1;
            }
        }
        else {
            $auth->{permissions} = {};
        }

        $cb->( status 200, auth => $auth, tags => $tags );

        return;
    };

    if ($private_token) {

        # verify token
        $self->_verify_token_hash(
            $private_token,
            $res->{hash},
            sub ($status) {

                # token valid
                if ($status) {
                    $continue->();
                }

                # token is invalid
                else {
                    $cb->($status);
                }

                return;
            }
        );
    }
    else {
        $continue->();
    }

    return;
}

# APP
sub get_app ( $self, $app_id, $cb ) {
    if ( $app_id =~ /\A\d+\z/sm ) {
        if ( my $app = $self->dbh->selectrow( q[SELECT * FROM api_app WHERE id = ?], [$app_id] ) ) {
            $cb->( status 200, app => $app );
        }
        else {

            # app not found
            $cb->( status [ 404, 'App not found' ] );
        }
    }
    else {
        if ( my $app = $self->dbh->selectrow( q[SELECT * FROM api_app WHERE name = ?], [$app_id] ) ) {
            $cb->( status 200, app => $app );
        }
        else {

            # app not found
            $cb->( status [ 404, 'App not found' ] );
        }
    }

    return;
}

sub set_app_enabled ( $self, $app_id, $enabled, $cb ) {
    $self->get_app(
        $app_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $app = $res->{app};

            if ( ( $enabled && !$app->{enabled} ) || ( !$enabled && $app->{enabled} ) ) {
                if ( $self->dbh->do( q[UPDATE OR IGNORE api_app SET enabled = ? WHERE id = ?], [ !!$enabled, $app->{id} ] ) ) {
                    $cb->( status 200 );
                }
                else {
                    $cb->( status [ 500, 'Error set app enabled' ] );
                }
            }
            else {

                # not modified
                $cb->( status 304 );
            }

            return;
        }
    );

    return;
}

sub remove_app ( $self, $app_id, $cb ) {
    $self->get_app(
        $app_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            if ( $self->dbh->do( q[DELETE OR IGNORE FROM api_app WHERE id = ?], [ $res->{app}->{id} ] ) ) {
                $cb->( status 200 );
            }
            else {
                $cb->( status [ 404, 'Error removing app' ] );
            }

            return;
        }
    );

    return;
}

# APP ROLE
sub get_app_role ( $self, $role_id, $cb ) {

    # role_id is role id
    if ( $role_id =~ /\A\d+\z/sm ) {
        if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app_role WHERE id = ?], [$role_id] ) ) {
            $cb->( status 200, role => $role );
        }
        else {
            $cb->( status [ 404, qq[App role "$role_id" not found] ] );
        }
    }

    # role id is app_id/role_name
    else {
        my ( $app_id, $role_name ) = split m[/]sm, $role_id;

        # $app_id is app id
        if ( $app_id =~ /\A\d+\z/sm ) {
            if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app_role WHERE app_id = ? AND name = ?], [ $app_id, $role_name ] ) ) {
                $cb->( status 200, role => $role );
            }
            else {
                $cb->( status [ 404, qq[App role "$role_id" not found] ] );
            }
        }

        # $app_id is app name
        else {
            if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app, api_app_role WHERE api_app.name = ? AND api_app.id = api_app_role.app_id AND api_app_role.name = ?], [ $app_id, $role_name ] ) ) {
                $cb->( status 200, role => $role );
            }
            else {
                $cb->( status [ 404, qq[App role "$role_id" not found] ] );
            }
        }
    }

    return;
}

sub set_app_role_enabled ( $self, $role_id, $enabled, $cb ) {
    $self->get_app_role(
        $role_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $role = $res->{role};

            if ( ( $enabled && !$role->{enabled} ) || ( !$enabled && $role->{enabled} ) ) {
                if ( $self->dbh->do( q[UPDATE OR IGNORE api_app_role SET enabled = ? WHERE id = ?], [ !!$enabled, $role->{id} ] ) ) {
                    $cb->( status 200 );
                }
                else {
                    $cb->( status [ 500, 'Error set app role enabled' ] );
                }
            }
            else {

                # not modified
                $cb->( status 304 );
            }

            return;
        }
    );

    return;
}

# APP PERMISSIONS

# APP INSTANCE
sub get_app_instance ( $self, $app_instance_id, $cb ) {
    if ( my $app_instance = $self->dbh->selectrow( q[SELECT * FROM api_app_instance WHERE id = ?], [$app_instance_id] ) ) {
        delete $app_instance->{hash};

        $cb->( status 200, app_instance => $app_instance );
    }
    else {
        $cb->( status [ 404, 'App instance not found' ] );
    }

    return;
}

sub set_app_instance_token ( $self, $app_instance_id, $cb ) {
    $self->_generate_app_instance_token(
        $app_instance_id,
        sub ( $res ) {

            # app instance token generation error
            if ( !$res ) {
                $cb->($res);
            }

            # app instance token generated
            else {

                # set app instance token
                if ( $self->dbh->do( q[UPDATE api_app_instance SET hash = ? WHERE id = ?], [ $res->{hash}, $app_instance_id ] ) ) {
                    $cb->( status 200, token => $res->{token} );
                }

                # set token error
                else {
                    $cb->( status [ 500, 'Error creation app instance token' ] );
                }
            }

            return;
        }
    );

    return;
}

sub set_app_instance_enabled ( $self, $app_instance_id, $enabled, $cb ) {
    $self->get_app_instance(
        $app_instance_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            if ( ( $enabled && !$res->{app_instance}->{enabled} ) || ( !$enabled && $res->{app_instance}->{enabled} ) ) {
                if ( $self->dbh->do( q[UPDATE api_app_instance SET enabled = ? WHERE id = ?], [ !!$enabled, $app_instance_id ] ) ) {
                    $cb->( status 200 );
                }
                else {
                    $cb->( status [ 500, 'Error set app instance enabled' ] );
                }
            }
            else {

                # not modified
                $cb->( status 304 );
            }

            return;
        }
    );

    return;
}

sub remove_app_instance ( $self, $app_instance_id, $cb ) {
    if ( $self->dbh->do( q[DELETE FROM api_app_instance WHERE id = ?], [$app_instance_id] ) ) {
        $cb->( status 200 );
    }
    else {
        $cb->( status [ 404, 'Error remmoving app instance' ] );
    }

    return;
}

sub get_app_instance_roles ( $self, $app_id, $cb ) {
    if ( my $roles = $self->dbh->selectall( q[SELECT id, name, enabled FROM api_app_role WHERE app_id = ?], [$app_id] ) ) {
        $cb->( status 200, roles => $roles );
    }
    else {
        $cb->( status 200, roles => [] );
    }

    return;
}

# USER
sub get_users ( $self, $cb ) {
    if ( my $users = $self->dbh->selectall(q[SELECT * FROM api_user]) ) {
        for my $row ( $users->@* ) {
            delete $row->{hash};
        }

        $cb->( status 200, users => $users );
    }
    else {
        $cb->( status 500 );
    }

    return;
}

sub get_user ( $self, $user_id, $cb ) {
    if ( $user_id =~ /\A\d+\z/sm ) {
        if ( my $user = $self->dbh->selectrow( q[SELECT * FROM api_user WHERE id = ?], [$user_id] ) ) {
            delete $user->{hash};

            $cb->( status 200, user => $user );
        }
        else {

            # user not found
            $cb->( status [ 404, 'User not found' ] );
        }
    }
    else {
        if ( my $user = $self->dbh->selectrow( q[SELECT * FROM api_user WHERE name = ?], [$user_id] ) ) {
            delete $user->{hash};

            $cb->( status 200, user => $user );
        }
        else {

            # user not found
            $cb->( status [ 404, 'User not found' ] );
        }
    }

    return;
}

# TODO permissions, enabled
sub create_user ( $self, $user_name, $password, $cb ) {
    my $dbh = $self->dbh;

    # user created
    if ( $dbh->do( q[INSERT OR IGNORE INTO api_user (name, enabled, created_ts) VALUES (?, ?, ?)], [ $user_name, 0, time ] ) ) {
        my $user_id = $dbh->last_insert_id;

        # set password
        $self->set_user_password(
            $user_id,
            $password,
            sub ($status) {
                if ($status) {

                    # enable user
                    $self->set_user_enabled(
                        $user_id, 1,
                        sub ($status) {
                            if ($status) {
                                $cb->( status 201, user_id => $user_id );
                            }
                            else {
                                # rollback
                                $dbh->do( q[DELETE OR IGNORE FROM api_user WHERE id = ?], [$user_id] );

                                $cb->($status);
                            }

                            return;
                        }
                    );
                }
                else {

                    # rollback
                    $dbh->do( q[DELETE OR IGNORE FROM api_user WHERE id = ?], [$user_id] );

                    $cb->($status);
                }

                return;
            }
        );
    }

    # user already exists
    else {
        my $user_id = $dbh->selectval( 'SELECT id FROM api_user WHERE name = ?', [$user_name] )->$*;

        # name already exists
        $cb->( status [ 409, 'User already exists' ], user_id => $user_id );
    }

    return;
}

sub set_user_password ( $self, $user_id, $user_password_utf8, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $user = $res->{user};

            $self->_generate_user_password_hash(
                $user->{name},
                $user_password_utf8,
                sub ( $res ) {
                    if ( !$res ) {
                        $cb->($res);

                        return;
                    }

                    if ( !$self->dbh->do( q[UPDATE api_user SET hash = ? WHERE id = ?], [ $res->{hash}, $user->{id} ] ) ) {
                        $cb->( status [ 500, 'Error setting user password' ] );

                        return;
                    }

                    $cb->( status 200 );

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub set_user_enabled ( $self, $user_id, $enabled, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            if ( ( $enabled && !$res->{user}->{enabled} ) || ( !$enabled && $res->{user}->{enabled} ) ) {
                if ( $self->dbh->do( q[UPDATE OR IGNORE api_user SET enabled = ? WHERE id = ?], [ !!$enabled, $res->{user}->{id} ] ) ) {
                    $cb->( status 200 );
                }
                else {
                    $cb->( status [ 500, 'Error set user enabled' ] );
                }
            }
            else {

                # not modified
                $cb->( status 304 );
            }

            return;
        }
    );

    return;
}

# USER PERMISSIONS
sub get_user_permissions ( $self, $user_id, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $res ) {

            # get user error
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $permissions;

            # root user
            if ( $res->{user}->{id} == 1 || $res->{user}->{name} eq 'root' ) {
                $permissions = $self->dbh->selectall(
                    <<'SQL'
                    SELECT
                        NULL AS id,
                        1 AS enabled,
                        api_app_role.id AS role_id,
                        api_app_role.name AS role_name,
                        api_app_role.[desc] AS role_desc,
                        api_app_role.enabled AS role_enabled,
                        api_app.id AS app_id,
                        api_app.name AS app_name,
                        api_app.enabled AS app_enabled
                    FROM
                        api_app_role,
                        api_app
                    WHERE
                        api_app_role.app_id = api_app.id
                        AND api_app_role.enabled = 1
SQL
                );
            }

            # not root user
            else {
                $permissions = $self->dbh->selectall(
                    <<'SQL',
                    SELECT
                        api_user_permissions.id,
                        api_user_permissions.enabled,
                        api_app_role.id AS role_id,
                        api_app_role.name AS role_name,
                        api_app_role.[desc] AS role_desc,
                        api_app_role.enabled AS role_enabled,
                        api_app.id AS app_id,
                        api_app.name AS app_name,
                        api_app.enabled AS app_enabled
                    FROM
                        api_user_permissions,
                        api_app_role,
                        api_app
                    WHERE
                        api_user_permissions.user_id = ?
                        AND api_user_permissions.role_id = api_app_role.id
                        AND api_app_role.app_id = api_app.id
                        AND api_app_role.enabled = 1
SQL
                    [ $res->{user}->{id} ]
                );
            }

            if ($permissions) {
                $cb->( status 200, user_permissions => $permissions );
            }
            else {
                $cb->( status 200, user_permissions => [] );
            }

            return;
        }
    );

    return;
}

sub set_user_permissions ( $self, $creator_user_id, $user_id, $permissions, $cb ) {

    # root user
    if ( $user_id =~ /\A(1|root)\z/sm ) {
        $cb->( status 304 );

        return;
    }

    # not root user, get creator permissions
    $self->get_user_permissions(
        $creator_user_id,
        sub ( $res ) {

            # get permissions error
            if ( !$res ) {
                $cb->($res);

                return;
            }

            # creator permissions, indexed by role_id
            my $creator_permissions = { map { $_->{role_id} => $_ } $res->{user_permissions}->@* };

            # get user permissions
            $self->get_user_permissions(
                $user_id,
                sub ($res) {

                    # get permissions error
                    if ( !$res ) {
                        $cb->($res);

                        return;
                    }

                    # user permissions, indexed by role_id
                    my $user_permissions = { map { $_->{role_id} => $_ } $res->{user_permissions}->@* };

                    my ( $role_error, $roles );

                    my $cv = AE::cv sub {
                        if ($role_error) {
                            $cb->( status [ 400, 'Invalid permissions: ' . join q[, ], $role_error->@* ] );

                            return;
                        }

                        my $add_roles;

                        for my $role_id ( keys $roles->%* ) {

                            # role doesn't exists in the base creator user permissions
                            if ( !exists $creator_permissions->{$role_id} ) {
                                $cb->( status [ 400, qq[Invalid permission: $role_id] ] );

                                return;
                            }

                            # role should be added
                            if ( !exists $user_permissions->{$role_id} ) {
                                push $add_roles->@*, $role_id;
                            }
                        }

                        my $remove_roles;

                        for my $role_id ( keys $user_permissions->%* ) {

                            # role should be removed
                            push $remove_roles->@*, $role_id if !exists $roles->{$role_id};
                        }

                        if ( $add_roles || $remove_roles ) {
                            my $dbh = $self->dbh;

                            $dbh->begin_work;

                            if ($remove_roles) {
                                my $res = eval { $dbh->do( [ q[DELETE FROM api_user_permissions WHERE id IN], $remove_roles ] ) };

                                if ($@) {
                                    $dbh->rollback;

                                    $cb->( status 400 );
                                }
                            }

                            if ($add_roles) {

                                # resolve user id
                                $self->get_user(
                                    $user_id,
                                    sub ($res) {
                                        if ( !$res ) {
                                            $dbh->rollback;

                                            $cb->($res);

                                            return;
                                        }

                                        for my $role_id ( $add_roles->@* ) {
                                            if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_permissions (user_id, role_id, enabled) VALUES (?, ?, 1) ], [ $res->{user}->{id}, $role_id ] ) ) {
                                                $dbh->rollback;

                                                $cb->( status 400 );

                                                return;
                                            }
                                        }

                                        $dbh->commit;

                                        $cb->( status 200 );

                                        return;
                                    }
                                );
                            }
                            else {
                                $dbh->commit;

                                $cb->( status 200 );
                            }
                        }

                        # nothing to do
                        else {

                            # not modified
                            $cb->( status 304 );
                        }

                        return;
                    };

                    $cv->begin;

                    # resolve permissions
                    for my $permission ( $permissions->@* ) {
                        $cv->begin;

                        $self->get_app_role(
                            $permission,
                            sub ($res) {
                                if ( !$res ) {
                                    push $role_error->@*, $permission;
                                }
                                else {
                                    $roles->{ $res->{role}->{id} } = $res->{role};
                                }

                                $cv->end;

                                return;
                            }
                        );
                    }

                    $cv->end;

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub add_user_permissions ( $self, $creator_user_id, $user_id, $permissions, $cb ) {

    # root user
    if ( $user_id =~ /\A(1|root)\z/sm ) {
        $cb->( status 304 );

        return;
    }

    # not root user, get creator permissions
    $self->get_user_permissions(
        $creator_user_id,
        sub ( $res ) {

            # get permissions error
            if ( !$res ) {
                $cb->($res);

                return;
            }

            # creator permissions, indexed by role_id
            my $creator_permissions = { map { $_->{role_id} => $_ } $res->{user_permissions}->@* };

            # get user permissions
            $self->get_user_permissions(
                $user_id,
                sub ($res) {

                    # get permissions error
                    if ( !$res ) {
                        $cb->($res);

                        return;
                    }

                    # user permissions, indexed by role_id
                    my $user_permissions = { map { $_->{role_id} => $_ } $res->{user_permissions}->@* };

                    my ( $role_error, $roles );

                    my $cv = AE::cv sub {
                        if ($role_error) {
                            $cb->( status [ 400, 'Invalid permissions: ' . join q[, ], $role_error->@* ] );

                            return;
                        }

                        my $add_roles;

                        for my $role_id ( keys $roles->%* ) {

                            # role doesn't exists in the base creator user permissions
                            if ( !exists $creator_permissions->{$role_id} ) {
                                $cb->( status [ 400, qq[Invalid permission: $role_id] ] );

                                return;
                            }

                            # role should be added
                            if ( !exists $user_permissions->{$role_id} ) {
                                push $add_roles->@*, $role_id;
                            }
                        }

                        # add roles
                        if ($add_roles) {

                            # resolve user id
                            $self->get_user(
                                $user_id,
                                sub ($res) {
                                    if ( !$res ) {
                                        $cb->($res);

                                        return;
                                    }

                                    my $user_id = $res->{user}->{id};

                                    my $dbh = $self->dbh;

                                    $dbh->begin_work;

                                    for my $role_id ( $add_roles->@* ) {
                                        if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_permissions (user_id, role_id, enabled) VALUES (?, ?, 1) ], [ $user_id, $role_id ] ) ) {
                                            $dbh->rollback;

                                            $cb->( status [ 400, qq[Error creating user permission: $role_id] ] );

                                            return;
                                        }
                                    }

                                    $dbh->commit;

                                    $cb->( status 200 );

                                    return;
                                }
                            );
                        }

                        # nothing to do
                        else {

                            # not modified
                            $cb->( status 304 );
                        }

                        return;
                    };

                    $cv->begin;

                    # resolve permissions
                    for my $permission ( $permissions->@* ) {
                        $cv->begin;

                        $self->get_app_role(
                            $permission,
                            sub ($res) {
                                if ( !$res ) {
                                    push $role_error->@*, $permission;
                                }
                                else {
                                    $roles->{ $res->{role}->{id} } = $res->{role};
                                }

                                $cv->end;

                                return;
                            }
                        );
                    }

                    $cv->end;

                    return;
                }
            );

            return;
        }
    );

    return;
}

# USER TOKEN
sub get_user_token ( $self, $user_token_id, $cb ) {
    if ( my $user_token = $self->dbh->selectrow( q[SELECT * FROM api_user_token WHERE id = ?], [$user_token_id] ) ) {
        delete $user_token->{hash};

        $cb->( status 200, user_token => $user_token );
    }
    else {

        # user token not found
        $cb->( status [ 404, 'User token not found' ] );
    }

    return;
}

sub create_user_token ( $self, $user_id, $desc, $permissions, $cb ) {

    # root user
    if ( $user_id =~ /\A(1|root)\z/sm ) {
        $cb->( status [ 400, 'Root user token creation error' ] );

        return;
    }

    # not root user, resolve user_id, get user
    $self->get_user(
        $user_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $user = $res->{user};

            my $dbh = $self->dbh;

            # get app roles
            my $user_permissions;

            for my $role_id ( $permissions->@* ) {
                next if exists $user_permissions->{$role_id};

                $self->get_app_role(
                    $role_id,
                    sub ( $res ) {
                        if ( !$res ) {
                            $cb->($res);

                            return;
                        }

                        # get user_permission for role
                        my $user_permission = $self->dbh->selectrow( q[SELECT id FROM api_user_permissions WHERE user_id = ? AND role_id = ?], [ $user->{id}, $res->{role}->{id} ] );
                        if ( !$user_permission ) {
                            $cb->( status [ 400, qq[User permission "$role_id" not exists] ] );

                            return;
                        }

                        $user_permissions->{$role_id} = $user_permission->{id};
                    }
                );
            }

            # generate user token hash
            $self->_generate_user_token(
                $user->{id},
                sub ( $res ) {
                    if ( !$res ) {
                        $cb->( status [ 500, 'User token creation error' ] );

                        return;
                    }

                    my $user_token_id = $res->{token_id};

                    # insert user token
                    if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_token (id, user_id, desc, created_ts, enabled, hash) VALUES (?, ?, ?, ?, 0, ?)], [ $user_token_id, $user->{id}, $desc // q[], time, $res->{hash} ] ) ) {
                        $cb->( status [ 500, 'User token creation error' ] );

                        return;
                    }

                    # create user token permissions
                    for my $user_permission_id ( values $user_permissions->%* ) {
                        if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_token_permissions (user_token_id, user_permissions_id) VALUES (?, ?)], [ $user_token_id, $user_permission_id ] ) ) {

                            # rollback
                            $dbh->do( q[DELETE FROM api_user_token WHERE id = ?], [$user_token_id] );

                            $cb->( status [ 500, 'User token creation error' ] );

                            return;
                        }
                    }

                    # enable user token
                    $dbh->do( q[UPDATE api_user_token SET enabled = 1 WHERE id = ?], [$user_token_id] );

                    $cb->( status 201, token => $res->{token} );

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub set_user_token_enabled ( $self, $user_token_id, $enabled, $cb ) {
    $self->get_user_token(
        $user_token_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);
            }
            else {
                my $user_token = $res->{user_token};

                if ( ( $enabled && !$user_token->{enabled} ) || ( !$enabled && $user_token->{enabled} ) ) {
                    if ( $self->dbh->do( q[UPDATE OR IGNORE api_user_token SET enabled = ? WHERE id = ?], [ !!$enabled, $user_token->{id} ] ) ) {
                        $cb->( status 200 );
                    }
                    else {
                        $cb->( status [ 500, 'Error set user token enabled' ] );
                    }
                }
                else {

                    # not modified
                    $cb->( status 304 );
                }
            }

            return;
        }
    );

    return;
}

sub remove_user_token ( $self, $user_token_id, $cb ) {
    if ( $self->dbh->do( q[DELETE OR IGNORE FROM api_user_token WHERE id = ?], [$user_token_id] ) ) {
        $cb->( status 200 );
    }
    else {
        $cb->( status [ 404, 'User token not found' ] );
    }

    return;
}

# USER SESSION
# TODO
sub create_user_session ( $self, $user_id, $user_agent, $remote_ip, $remote_ip_geo, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $user = $res->{user};

            my $dbh = $self->dbh;

            # create blank user token
            if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_session (user_id, created_ts, user_agent, remote_ip, remote_ip_geo) VALUES (?, ?, ?, ?, ?)], [ $user->{id}, time, $user_agent, $remote_ip, $remote_ip_geo ] ) ) {
                $cb->( status [ 500, 'User session creation error' ] );

                return;
            }

            # get user token id
            my $user_session_id = $dbh->last_insert_id;

            # generate user token hash
            $self->_generate_user_session(
                $user_session_id,
                sub ( $res ) {
                    if ( !$res ) {

                        # rollback
                        $dbh->do( q[DELETE FROM api_user_session WHERE id = ?], [$user_session_id] );

                        $cb->( status [ 500, 'User session creation error' ] );

                        return;
                    }

                    if ( !$dbh->do( q[UPDATE OR IGNORE api_user_session SET hash = ? WHERE id = ?], [ $res->{hash}, $user_session_id ] ) ) {

                        # rollback
                        $dbh->do( q[DELETE FROM api_user_session WHERE id = ?], [$user_session_id] );

                        $cb->( status [ 500, 'User session creation error' ] );

                        return;
                    }

                    $cb->( status 201, session => $res->{session} );

                    return;
                }
            );

            return;
        }
    );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 117, 229, 294, 328,  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 367, 423, 494, 590,  |                                                                                                                |
## |      | 690, 796, 1105,      |                                                                                                                |
## |      | 1260, 1413, 1586,    |                                                                                                                |
## |      | 1751, 1850, 1895     |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 |                      | Subroutines::ProhibitUnusedPrivateSubroutines                                                                  |
## |      | 229                  | * Private subroutine/method '_connect_app_instance' declared but not used                                      |
## |      | 494                  | * Private subroutine/method '_auth_user_password' declared but not used                                        |
## |      | 590                  | * Private subroutine/method '_auth_app_instance_token' declared but not used                                   |
## |      | 690                  | * Private subroutine/method '_auth_user_token' declared but not used                                           |
## |      | 796                  | * Private subroutine/method '_auth_user_session' declared but not used                                         |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 1413                 | Subroutines::ProhibitExcessComplexity - Subroutine "set_user_permissions" with high complexity score (23)      |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 1416, 1589, 1754     | RegularExpressions::ProhibitFixedStringMatches - Use 'eq' or hash instead of fixed-pattern regexps             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::sqlite

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
