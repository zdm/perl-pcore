package Pcore::App::API::Backend::Local::sqlite;

use Pcore -class, -status;

with qw[Pcore::App::API::Backend::Local::sqlite::Auth];

with qw[Pcore::App::API::Backend::Local::sqlite::App];
with qw[Pcore::App::API::Backend::Local::sqlite::AppRole];

with qw[Pcore::App::API::Backend::Local::sqlite::AppInstance];

with qw[Pcore::App::API::Backend::Local::sqlite::User];
with qw[Pcore::App::API::Backend::Local::sqlite::UserPermission];
with qw[Pcore::App::API::Backend::Local::sqlite::UserToken];
with qw[Pcore::App::API::Backend::Local::sqlite::UserSession];

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
                `app_id` INTEGER NOT NULL REFERENCES `api_app` (`id`) ON DELETE RESTRICT,
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 128, 240, 305, 339,  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 378, 434             |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 240                  | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_connect_app_instance' declared but |
## |      |                      |  not used                                                                                                      |
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
