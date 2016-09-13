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
sub get_apps ( $self, $cb ) {
    if ( my $apps = $self->dbh->selectall(q[SELECT * FROM api_app]) ) {
        $cb->( status 200, $apps );
    }
    else {
        $cb->( status 200, [] );
    }

    return;
}

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

sub _create_app ( $self, $app_name, $app_desc, $cb ) {
    my $dbh = $self->dbh;

    # app created
    if ( $dbh->do( q[INSERT OR IGNORE INTO api_app (name, desc, enabled, created_ts) VALUES (?, ?, ?, ?)], [ $app_name, $app_desc, 1, time ] ) ) {
        my $app_id = $dbh->last_insert_id;

        $cb->( status 201, $app_id );
    }

    # app creation error
    else {
        my $app_id = $dbh->selectval( 'SELECT id FROM api_app WHERE name = ?', [$app_name] )->$*;

        # app already exists
        $cb->( status [ 409, 'App already exists' ], $app_id );
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

# TODO merge with create_app
sub add_app_roles ( $self, $app_id, $app_roles, $cb ) {
    my $modified;

    my $cv = AE::cv sub {
        if   ($modified) { $cb->( status 200 ) }
        else             { $cb->( status 304 ) }

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
sub get_app_germissions ( $self, $app_id, $cb ) {
    if ( my $permissions = $self->dbh->selectall( q[SELECT * FROM api_app_permissions WHERE app_id = ?], [$app_id] ) ) {
        $cb->( status 200, $permissions );
    }
    else {
        $cb->( status 200, [] );
    }

    return;
}

# TODO merge with create_app
sub add_app_permissions ( $self, $app_id, $app_permissions, $cb ) {
    if ( !$app_permissions || !keys $app_permissions->%* ) {
        $cb->( status 200 );

        return;
    }

    my $error;

    my $cv = AE::cv sub {
        if ($error) {
            $cb->( status [ 400, join q[, ], $error->@* ] );
        }
        else {
            $cb->( status 200 );
        }

        return;
    };

    $cv->begin;

    for my $app_name ( keys $app_permissions->%* ) {
        $cv->begin;

        # resolve role id
        $self->get_app(
            $app_name,
            sub ( $status, $app ) {
                if ( !$status ) {
                    push $error->@*, $app_name;
                }
                else {
                    $self->get_app_role(
                        "$app->{id}/app",
                        sub ( $status, $role ) {
                            if ( !$status ) {
                                push $error->@*, $app_name;
                            }
                            else {

                                # create new disabled permisison record
                                $self->dbh->do( q[INSERT OR IGNORE INTO api_app_permissions (app_id, role_id, enabled) VALUES (?, ?, 0)], [ $app_id, $role->{id} ] );

                                $cv->end;
                            }

                            return;
                        }
                    );
                }
            }
        );
    }

    $cv->end;

    return;
}

sub app_permissions_enable_all ( $self, $app_id, $cb ) {
    if ( $self->dbh->do( q[UPDATE api_app_permissions SET enabled = 1 WHERE app_id = ?], [$app_id] ) ) {

        # updated
        $cb->( status 200 );
    }
    else {

        # not modified
        $cb->( status 304 );
    }

    return;
}

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

sub _create_app_instance ( $self, $app_id, $app_instance_host, $app_instance_version, $cb ) {
    $self->get_app(
        $app_id,
        sub ( $status, $role ) {

            # app not found
            if ( !$status ) {
                $cb->( $status, undef );
            }

            # app found
            else {

                # app instance created
                if ( $self->dbh->do( q[INSERT OR IGNORE INTO api_app_instance (app_id, host, version, enabled, created_ts) VALUES (?, ?, ?, 0, ?)], [ $app_id, $app_instance_host, $app_instance_version, time ] ) ) {
                    my $app_instance_id = $self->dbh->last_insert_id;

                    $cb->( status 201, $app_instance_id );
                }

                # app instance creation error
                else {
                    $cb->( status [ 500, 'App instance creation error' ], undef );
                }
            }

            return;
        }
    );

    return;
}

sub update_app_instance ( $self, $app_instance_id, $app_instance_version, $cb ) {
    if ( $self->dbh->do( q[UPDATE OR IGNORE api_app_instance SET version = ?, last_connected_ts = ? WHERE id = ?], [ $app_instance_version, time, $app_instance_id ] ) ) {
        $cb->( status 200 );
    }
    else {
        $cb->( status [ 404, 'App instance not found' ] );
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

                    if ( !$self->dbh->do( q[UPDATE api_user SET hash = ? WHERE id = ?], [ $hash, $user_id ] ) ) {
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

            my $error;

            my $cv = AE::cv sub {
                if ($error) {
                    $dbh->rollback;

                    $cb->( status [ 500, 'Set user permissions error' ] );
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
                        elsif ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_permissions (user_id, role_id, enabled) VALUES (?, ?, 1)], [ $user_id, $role->{id} ] ) ) {
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

sub create_user_token ( $self, $user_id, $permissions, $cb ) {
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
            if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_token (user_id, created_ts, enabled) VALUES (?, ?, 0)], [ $user_id, time ] ) ) {
                $dbh->rollback;

                $cb->( status [ 500, 'User token creation error' ], undef );

                return;
            }

            # get user token id
            my $user_token_id = $dbh->last_insert_id;

            # create user token permissions
            for my $user_permission_id ( $permissions->@* ) {

                # symbolic permission (app_name/role_name)
                if ( $user_permission_id !~ /\A\d+\z/sm ) {
                    my ( $app_name, $role_name ) = split m[/]sm, $user_permission_id;

                    unless ( my $row = $dbh->selectrow( q[SELECT api_user_permissions.id FROM api_app, api_app_role, api_user_permissions WHERE api_app.name = ? AND api_app_role.name = ? AND api_app_role.app_id = api_app.id AND api_app_role.id = api_user_permissions.role_id AND api_user_permissions.user_id = ?], [ $app_name, $role_name, $user_id ] ) ) {
                        $dbh->rollback;

                        $cb->( status [ 500, 'User token creation error' ], undef );

                        return;
                    }
                    else {
                        $user_permission_id = $row->{id};
                    }
                }

                if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_token_permissions (user_token_id, user_permissions_id) VALUES (?, ?)], [ $user_token_id, $user_permission_id ] ) ) {
                    $dbh->rollback;

                    $cb->( status [ 500, 'User token creation error' ], undef );

                    return;
                }
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

sub remove_user_token ( $self, $token_id, $cb ) {
    if ( $self->dbh->do( q[DELETE FROM api_user_token WHERE id = ?], [$token_id] ) ) {
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
## |    3 | 105, 201, 301, 443,  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 554, 621, 710, 743,  |                                                                                                                |
## |      | 785, 924, 1057, 1173 |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 |                      | Subroutines::ProhibitUnusedPrivateSubroutines                                                                  |
## |      | 105                  | * Private subroutine/method '_auth_user_password' declared but not used                                        |
## |      | 201                  | * Private subroutine/method '_auth_app_instance_token' declared but not used                                   |
## |      | 301                  | * Private subroutine/method '_auth_user_token' declared but not used                                           |
## |      | 443                  | * Private subroutine/method '_create_app' declared but not used                                                |
## |      | 710                  | * Private subroutine/method '_create_app_instance' declared but not used                                       |
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
