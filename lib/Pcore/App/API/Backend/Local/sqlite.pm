package Pcore::App::API::Backend::Local::sqlite;

use Pcore -class;
use Pcore::Util::Status::Keyword qw[status];

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
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `created_ts` INTEGER,
                `user_id` INTEGER NOT NULL REFERENCES `api_user` (`id`) ON DELETE CASCADE,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `desc` TEXT,
                `hash` BLOB UNIQUE
            );

            --- USER TOKEN PERMISSIONS
            CREATE TABLE IF NOT EXISTS `api_user_token_permissions` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `user_token_id` INTEGER NOT NULL REFERENCES `api_user_token` (`id`) ON DELETE CASCADE,
                `user_permissions_id` INTEGER NOT NULL REFERENCES `api_user_permissions` (`id`) ON DELETE CASCADE
            );

            CREATE UNIQUE INDEX `idx_uniq_api_user_token_permissions` ON `api_user_token_permissions` (`user_token_id`, `user_permissions_id`);
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
        sub ( $status, $app ) {
            my $dbh = $self->dbh;

            $dbh->begin_work;

            my $app_id;

            # app exists
            if ($status) {

                # app is disabled, registration is disallowed
                if ( !$app->{enabled} ) {
                    $dbh->rollback;

                    $cb->( status [ 400, 'App is disabled' ], undef, undef );

                    return;
                }

                $app_id = $app->{id};
            }

            # app is not exists, create app
            else {

                # app creation error
                if ( !$dbh->do( q[INSERT OR IGNORE INTO api_app (name, desc, enabled, created_ts) VALUES (?, ?, 0, ?)], [ $app_name, $app_desc, time ] ) ) {
                    $dbh->rollback;

                    $cb->( status [ 500, 'Error creation app' ], undef, undef );

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

                        $cb->( $status, undef, undef );

                        return;
                    }

                    # create disabled app instance
                    if ( !$dbh->do( q[INSERT OR IGNORE INTO api_app_instance (app_id, host, version, enabled, created_ts) VALUES (?, ?, ?, 0, ?)], [ $app_id, $app_instance_host, $app_instance_version, time ] ) ) {

                        # app instance creation error
                        $dbh->rollback;

                        $cb->( status [ 500, 'App instance creation error' ], undef, undef );

                        return;
                    }

                    my $app_instance_id = $dbh->last_insert_id;

                    # set app instance token
                    $self->_generate_app_instance_token(
                        $app_instance_id,
                        sub ( $status, $app_instance_token, $hash ) {

                            # app instance token generation error
                            if ( !$status ) {
                                $dbh->rollback;

                                $cb->( $status, undef );

                                return;
                            }

                            # store app instance token
                            if ( !$dbh->do( q[UPDATE api_app_instance SET hash = ? WHERE id = ?], [ $hash, $app_instance_id ] ) ) {
                                $dbh->rollback;

                                $cb->( status [ 500, 'Error creation app instance token' ], undef, undef );

                                return;
                            }

                            # registration process finished successfully
                            $dbh->commit;

                            $cb->( status 201, $app_instance_id, $app_instance_token );

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
        sub ( $status, $app_instance ) {
            if ( !$status ) {
                $cb->($status);

                return;
            }

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
        sub ( $status, $root_password ) {
            if ( !$status && $status != 304 ) {
                $cb->($status);

                return;
            }

            if ($root_password) {
                say "Root user created: root / $root_password";
            }

            $self->{app}->{api}->connect_local_app_instance(
                sub ($status) {
                    $cb->($status);

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
            sub ( $status, $role ) {
                if ( !$status ) {
                    push $error->@*, $permission;
                }
                else {

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
        sub ( $status, $user ) {

            # user_id 1 already exists
            if ( $status != 404 ) {
                $cb->( status 304, undef );

                return;
            }

            my $root_password = P->data->to_b64_url( P->random->bytes(32) );

            $self->_generate_user_password_hash(
                'root',
                $root_password,
                sub ( $status, $hash ) {
                    if ( !$status ) {
                        $cb->( $status, undef );

                        return;
                    }

                    if ( $self->dbh->do( q[INSERT OR IGNORE INTO api_user (id, name, hash, enabled, created_ts) VALUES (1, ?, ?, 1, ?)], [ 'root', $hash, time ] ) ) {
                        $cb->( status 200, $root_password );
                    }
                    else {
                        $cb->( status [ 500, 'Error creating root' ], undef );
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
        $cb->( status [ 404, 'User not found' ], undef, undef );

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

        $cb->( status 200, $auth, $tags );

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
                    $cb->( $status, undef, undef );
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
        $cb->( status [ 404, 'App instance not found' ], undef, undef );

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

        $cb->( status 200, $auth, $tags );

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
                    $cb->( $status, undef, undef );
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

    # get user token instance
    my $res = $self->dbh->selectrow( $sql1, [$user_token_id] );

    # user token not found
    if ( !$res ) {
        $cb->( status [ 404, 'User token not found' ], undef, undef );

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

        $cb->( status 200, $auth, $tags );

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
                    $cb->( $status, undef, undef );
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
            $cb->( status 200, $app );
        }
        else {

            # app not found
            $cb->( status [ 404, 'App not found' ], undef );
        }
    }
    else {
        if ( my $app = $self->dbh->selectrow( q[SELECT * FROM api_app WHERE name = ?], [$app_id] ) ) {
            $cb->( status 200, $app );
        }
        else {

            # app not found
            $cb->( status [ 404, 'App not found' ], undef );
        }
    }

    return;
}

sub set_app_enabled ( $self, $app_id, $enabled, $cb ) {
    $self->get_app(
        $app_id,
        sub ( $status, $app ) {
            if ( !$status ) {
                $cb->($status);

                return;
            }

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
        sub ( $status, $app ) {
            if ( !$status ) {
                $cb->($status);

                return;
            }

            if ( $self->dbh->do( q[DELETE OR IGNORE FROM api_app WHERE id = ?], [ $app->{id} ] ) ) {
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
    if ( $role_id =~ /\A\d+\z/sm ) {
        if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app_role WHERE id = ?], [$role_id] ) ) {
            $cb->( status 200, $role );
        }
        else {
            $cb->( status 404, undef );
        }
    }
    else {
        my ( $app_id, $role_name ) = split m[/]sm, $role_id;

        if ( $app_id =~ /\A\d+\z/sm ) {
            if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app_role WHERE app_id = ? AND name = ?], [ $app_id, $role_name ] ) ) {
                $cb->( status 200, $role );
            }
            else {
                $cb->( status 404, undef );
            }
        }
        else {
            if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app, api_app_role WHERE api_app.name = ? AND api_app.id = api_app_role.app_id AND api_app_role.name = ?], [ $app_id, $role_name ] ) ) {
                $cb->( status 200, $role );
            }
            else {
                $cb->( status 404, undef );
            }
        }
    }

    return;
}

sub set_app_role_enabled ( $self, $role_id, $enabled, $cb ) {
    $self->get_app_role(
        $role_id,
        sub ( $status, $role ) {
            if ( !$status ) {
                $cb->($status);

                return;
            }

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

        $cb->( status 200, $app_instance );
    }
    else {
        $cb->( status [ 404, 'App instance not found' ], undef );
    }

    return;
}

sub set_app_instance_token ( $self, $app_instance_id, $cb ) {
    $self->_generate_app_instance_token(
        $app_instance_id,
        sub ( $status, $token, $hash ) {

            # app instance token generation error
            if ( !$status ) {
                $cb->( $status, undef );
            }

            # app instance token generated
            else {

                # set app instance token
                if ( $self->dbh->do( q[UPDATE api_app_instance SET hash = ? WHERE id = ?], [ $hash, $app_instance_id ] ) ) {
                    $cb->( status 200, $token );
                }

                # set token error
                else {
                    $cb->( status [ 500, 'Error creation app instance token' ], undef );
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
        sub ( $status, $app_instance ) {
            if ( !$status ) {
                $cb->($status);

                return;
            }

            if ( ( $enabled && !$app_instance->{enabled} ) || ( !$enabled && $app_instance->{enabled} ) ) {
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
        $cb->( status 200, $roles );
    }
    else {
        $cb->( status 200, [] );
    }

    return;
}

# USER
sub get_user ( $self, $user_id, $cb ) {
    if ( $user_id =~ /\A\d+\z/sm ) {
        if ( my $user = $self->dbh->selectrow( q[SELECT * FROM api_user WHERE id = ?], [$user_id] ) ) {
            delete $user->{hash};

            $cb->( status 200, $user );
        }
        else {

            # user not found
            $cb->( status [ 404, 'User not found' ], undef );
        }
    }
    else {
        if ( my $user = $self->dbh->selectrow( q[SELECT * FROM api_user WHERE name = ?], [$user_id] ) ) {
            delete $user->{hash};

            $cb->( status 200, $user );
        }
        else {

            # user not found
            $cb->( status [ 404, 'User not found' ], undef );
        }
    }

    return;
}

sub create_user ( $self, $user_name, $password, $cb ) {
    my $dbh = $self->dbh;

    $dbh->begin_work;

    # user created
    if ( $dbh->do( q[INSERT OR IGNORE INTO api_user (name, enabled, created_ts) VALUES (?, ?, ?)], [ $user_name, 0, time ] ) ) {
        my $user_id = $dbh->last_insert_id;

        $self->set_user_password(
            $user_id,
            $password,
            sub ($status) {
                if ($status) {
                    $self->set_user_enabled(
                        $user_id, 1,
                        sub ($status) {
                            if ($status) {
                                $dbh->commit;

                                $cb->( status 201, $user_id );
                            }
                            else {
                                $dbh->rollback;

                                $cb->( $status, undef );
                            }

                            return;
                        }
                    );
                }
                else {
                    $dbh->rollback;

                    $cb->( $status, undef );
                }

                return;
            }
        );
    }

    # user already exists
    else {
        $dbh->rollback;

        my $user_id = $dbh->selectval( 'SELECT id FROM api_user WHERE name = ?', [$user_name] )->$*;

        # name already exists
        $cb->( status [ 409, 'User already exists' ], $user_id );
    }

    return;
}

sub set_user_password ( $self, $user_id, $user_password_utf8, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $status, $user ) {
            if ( !$status ) {
                $cb->($status);

                return;
            }

            $self->_generate_user_password_hash(
                $user->{name},
                $user_password_utf8,
                sub ( $status, $hash ) {
                    if ( !$status ) {
                        $cb->($status);

                        return;
                    }

                    if ( !$self->dbh->do( q[UPDATE api_user SET hash = ? WHERE id = ?], [ $hash, $user->{id} ] ) ) {
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
        sub ( $status, $user ) {
            if ( !$status ) {
                $cb->($status);
            }
            else {
                if ( ( $enabled && !$user->{enabled} ) || ( !$enabled && $user->{enabled} ) ) {
                    if ( $self->dbh->do( q[UPDATE OR IGNORE api_user SET enabled = ? WHERE id = ?], [ !!$enabled, $user->{id} ] ) ) {
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
            }

            return;
        }
    );

    return;
}

# USER PERMISSIONS
sub get_user_app_permissions ( $self, $user_id, $app_id, $cb ) {
    if ( my $permissions = $self->dbh->selectall( q[SELECT api_user_permissions.user_id, api_user_permissions.role_id, api_user_permissions.enabled, api_app_role.name FROM api_user_permissions LEFT JOIN api_app_role ON api_app_role.app_id = ? AND api_user_permissions.role_id = api_app_role.id WHERE api_user_permissions.user_id = ?], [ $app_id, $user_id ] ) ) {
        $cb->( status 200, $permissions );
    }
    else {
        $cb->( status 200, [] );
    }

    return;
}

sub add_user_permissions ( $self, $user_id, $permissions, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $status, $user ) {
            if ( !$status ) {
                $cb->($status);

                return;
            }

            my $dbh = $self->dbh;

            $dbh->begin_work;

            my ( $error, $modified );

            my $cv = AE::cv sub {
                if ($error) {
                    $dbh->rollback;

                    $cb->( status [ 500, 'Set user permissions error' ] );
                }
                elsif ( !$modified ) {
                    $dbh->commit;

                    $cb->( status 304 );
                }
                else {
                    $dbh->commit;

                    $cb->( status 200 );
                }

                return;
            };

            $cv->begin;

            # create user token permissions
            for my $role_id ( $permissions->@* ) {
                $cv->begin;

                $self->get_app_role(
                    $role_id,
                    sub ( $status, $role ) {
                        if ( !$status ) {
                            $error = 1;
                        }
                        elsif ( !$self->dbh->selectrow( q[SELECT id FROM api_user_permissions WHERE user_id = ? AND role_id = ?], [ $user_id, $role->{id} ] ) ) {
                            if ( $dbh->do( q[INSERT OR IGNORE INTO api_user_permissions (user_id, role_id, enabled) VALUES (?, ?, 1)], [ $user_id, $role->{id} ] ) ) {
                                $modified = 1;
                            }
                            else {
                                $error = 1;
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
    );

    return;
}

# USER TOKEN
sub get_user_token ( $self, $user_token_id, $cb ) {
    if ( my $user_token = $self->dbh->selectrow( q[SELECT * FROM api_user_token WHERE id = ?], [$user_token_id] ) ) {
        delete $user_token->{hash};

        $cb->( status 200, $user_token );
    }
    else {

        # user token not found
        $cb->( status [ 404, 'User token not found' ], undef );
    }

    return;
}

sub create_user_token ( $self, $user_id, $desc, $permissions, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $status, $user ) {
            if ( !$status ) {
                $cb->( $status, undef );

                return;
            }

            my $dbh = $self->dbh;

            $dbh->begin_work;

            # create blank user token
            if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_token (user_id, desc, created_ts, enabled) VALUES (?, ?, ?, 0)], [ $user->{id}, $desc // q[], time ] ) ) {
                $dbh->rollback;

                $cb->( status [ 500, 'User token creation error' ], undef );

                return;
            }

            # get user token id
            my $user_token_id = $dbh->last_insert_id;

            my $error;

            my $cv = AE::cv sub {
                if ($error) {
                    $dbh->rollback;

                    $cb->( status [ 500, 'User token creation error' ], undef );

                    return;
                }

                # generate user token hash
                $self->_generate_user_token(
                    $user_token_id,
                    sub ( $status, $token, $hash ) {
                        if ( !$status ) {
                            $dbh->rollback;

                            $cb->( status [ 500, 'User token creation error' ], undef );

                            return;
                        }

                        if ( !$dbh->do( q[UPDATE OR IGNORE api_user_token SET hash = ?, enabled = 1 WHERE id = ?], [ $hash, $user_token_id ] ) ) {
                            $dbh->rollback;

                            $cb->( status [ 500, 'User token creation error' ], undef );

                            return;
                        }

                        $dbh->commit;

                        $cb->( status 201, $token );

                        return;
                    }
                );

                return;
            };

            $cv->begin;

            # create user token permissions
            for my $role_id ( $permissions->@* ) {

                $cv->begin;

                $self->get_app_role(
                    $role_id,
                    sub ( $status, $role ) {

                        # app role not exists
                        if ( !$status ) {
                            $error = 1;
                        }

                        # user permission exists
                        elsif ( my $user_permission = $dbh->selectrow( q[SELECT id FROM api_user_permissions WHERE user_id = ? AND role_id = ?], [ $user->{id}, $role->{id} ] ) ) {

                            # error creating user token permission
                            if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_token_permissions (user_token_id, user_permissions_id) VALUES (?, ?)], [ $user_token_id, $user_permission->{id} ] ) ) {
                                $error = 1;
                            }
                        }

                        # user permission not exists
                        else {
                            $error = 1;
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

sub set_user_token_enabled ( $self, $user_token_id, $enabled, $cb ) {
    $self->get_user_token(
        $user_token_id,
        sub ( $status, $user_token ) {
            if ( !$status ) {
                $cb->($status);
            }
            else {
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 106, 218, 281, 315,  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 354, 409, 476, 572,  |                                                                                                                |
## |      | 672, 970, 1109,      |                                                                                                                |
## |      | 1179, 1279, 1393     |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 |                      | Subroutines::ProhibitUnusedPrivateSubroutines                                                                  |
## |      | 218                  | * Private subroutine/method '_connect_app_instance' declared but not used                                      |
## |      | 476                  | * Private subroutine/method '_auth_user_password' declared but not used                                        |
## |      | 572                  | * Private subroutine/method '_auth_app_instance_token' declared but not used                                   |
## |      | 672                  | * Private subroutine/method '_auth_user_token' declared but not used                                           |
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
