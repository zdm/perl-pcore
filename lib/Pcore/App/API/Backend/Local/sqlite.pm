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
                `user_id` INTEGER NOT NULL REFERENCES `api_user` (`id`) ON DELETE CASCADE, --- remove role assoc., on user delete
                `role_id` INTEGER NOT NULL REFERENCES `api_app_role` (`id`) ON DELETE RESTRICT, --- prevent deleting role, if has assigned users
                `enabled` INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (`user_id`, `role_id`)
            );

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
                `user_token_id` INTEGER NOT NULL REFERENCES `api_user_token` (`id`) ON DELETE CASCADE, --- remove role assoc., on user token delete
                `role_id` INTEGER NOT NULL REFERENCES `api_app_role` (`id`) ON DELETE RESTRICT, --- prevent deleting role, if has assigned users
                `enabled` INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (`user_token_id`, `role_id`)
            );
SQL
    );

    $ddl->upgrade;

    $cb->( status 200 );

    return;
}

# AUTH
sub auth_user_password ( $self, $user_name, $user_password, $cb ) {
    if ( my $user = $self->dbh->selectrow( q[SELECT * FROM api_user WHERE name = ?], [$user_name] ) ) {
        my $hash = delete $user->{hash};

        $self->validate_user_password_hash(
            $hash,
            $user_password,
            $user->{id},
            sub ($status) {
                $cb->( $status, $user );

                return;
            }
        );
    }
    else {
        $cb->( status [ 404, 'User not found' ], undef );
    }

    return;
}

sub auth_app_instance_token ( $self, $app_instance_id, $token, $cb ) {
    if ( my $app_instance = $self->dbh->selectrow( q[SELECT * FROM api_app_instance WHERE id = ?], [$app_instance_id] ) ) {
        my $hash = delete $app_instance->{hash};

        $self->verify_hash(
            $hash, $token,
            sub ($status) {
                if ($status) {
                    $cb->( $status, $app_instance );
                }
                else {
                    $cb->( $status, undef );
                }

                return;
            }
        );
    }
    else {
        $cb->( status [ 404, 'App instance not found' ], undef );
    }

    return;
}

sub auth_user_token ( $self, $user_token_id, $token, $cb ) {
    if ( my $user_token = $self->dbh->selectrow( q[SELECT * FROM api_user_token WHERE id = ?], [$user_token_id] ) ) {
        my $hash = delete $user_token->{hash};

        $self->validate_user_token_hash(
            $hash, $token,
            $user_token->{user_id},
            sub ($status) {
                if ($status) {
                    $cb->( $status, $user_token );
                }
                else {
                    $cb->( $status, undef );
                }

                return;
            }
        );
    }
    else {
        $cb->( status [ 404, 'User token not found' ], undef );
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

sub get_app_by_id ( $self, $app_id, $cb ) {
    if ( my $app = $self->dbh->selectrow( q[SELECT * FROM api_app WHERE id = ?], [$app_id] ) ) {
        $cb->( status 200, $app );
    }
    else {
        $cb->( status [ 404, 'App not found' ], undef );
    }

    return;
}

sub get_app_by_name ( $self, $app_name, $cb ) {
    if ( my $app = $self->dbh->selectrow( q[SELECT * FROM api_app WHERE name = ?], [$app_name] ) ) {
        $cb->( status 200, $app );
    }
    else {

        # app not found
        $cb->( status [ 404, 'App not found' ], undef );
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
    $self->get_app_by_id(
        $app_id,
        sub ( $status, $app ) {
            if ( !$status ) {
                $cb->($status);
            }
            else {
                if ( ( $enabled && !$app->{enabled} ) || ( !$enabled && $app->{enabled} ) ) {
                    $self->dbh->do( q[UPDATE api_app SET enabled = ? WHERE id = ?], [ $enabled, $app_id ] );

                    $cb->( status 200 );
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

sub remove_app ( $self, $app_id, $cb ) {
    if ( $self->dbh->do( q[DELETE FROM api_app WHERE id = ?], [$app_id] ) ) {
        $cb->( status 200 );
    }
    else {
        $cb->( status [ 404, 'App not found' ] );
    }

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
        $self->get_app_by_name(
            $app_name,
            sub ( $status, $app ) {
                if ( !$status ) {
                    push $error->@*, $app_name;
                }
                else {
                    $self->get_role_by_name(
                        $app->{id},
                        'app',
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
sub get_app_instance_by_id ( $self, $app_instance_id, $cb ) {
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
    $self->get_app_by_id(
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
    $self->generate_app_instance_token(
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
    $self->get_app_instance_by_id(
        $app_instance_id,
        sub ( $status, $app_instance ) {
            if ( !$status ) {
                $cb->($status);
            }
            else {
                if ( ( $enabled && !$app_instance->{enabled} ) || ( !$enabled && $app_instance->{enabled} ) ) {
                    $self->dbh->do( q[UPDATE api_app_instance SET enabled = ? WHERE id = ?], [ $enabled, $app_instance_id ] );

                    $cb->( status 200 );
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

sub remove_app_instance ( $self, $app_instance_id, $cb ) {
    if ( $self->dbh->do( q[DELETE FROM api_app_instance WHERE id = ?], [$app_instance_id] ) ) {
        $cb->( status 200 );
    }
    else {
        $cb->( status [ 404, 'Error remmoving app instance' ] );
    }

    return;
}

# APP ROLE
sub get_role_by_id ( $self, $role_id, $cb ) {
    if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app_role WHERE id = ?], [$role_id] ) ) {
        $cb->( status 200, $role );
    }
    else {
        $cb->( status [ 404, 'Role not found' ], undef );
    }

    return;
}

sub get_role_by_name ( $self, $app_id, $role_name, $cb ) {
    if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app_role WHERE app_id = ? AND name = ?], [ $app_id, $role_name ] ) ) {
        $cb->( status 200, $role );
    }
    else {

        # role not found
        $cb->( status [ 404, 'Role not found' ], undef );
    }

    return;
}

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

sub set_role_enabled ( $self, $role_id, $enabled, $cb ) {
    $self->get_role_by_id(
        $role_id,
        sub ( $status, $role ) {
            if ( !$status ) {
                $cb->($status);
            }
            else {
                if ( ( $enabled && !$role->{enabled} ) || ( !$enabled && $role->{enabled} ) ) {
                    $self->dbh->do( q[UPDATE api_app_role SET enabled = ? WHERE id = ?], [ $enabled, $role_id ] );

                    $cb->( status 200 );
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

sub remove_role ( $self, $role_id, $cb ) {
    if ( $self->dbh->do( q[DELETE OR IGNORE FROM api_app_role WHERE id = ?], [$role_id] ) ) {
        $cb->( status 200 );
    }
    else {
        $cb->( status [ 400, 'Error removing app role' ] );
    }

    return;
}

# USER
sub get_user_by_id ( $self, $user_id, $cb ) {
    if ( my $user = $self->dbh->selectrow( q[SELECT * FROM api_user WHERE id = ?], [$user_id] ) ) {
        delete $user->{hash};

        $cb->( status 200, $user );
    }
    else {

        # user not found
        $cb->( status [ 404, 'User not found' ], undef );
    }

    return;
}

sub get_user_by_name ( $self, $user_name, $cb ) {
    if ( my $user = $self->dbh->selectrow( q[SELECT * FROM api_user WHERE name = ?], [$user_name] ) ) {
        delete $user->{hash};

        $cb->( status 200, $user );
    }
    else {

        # user not found
        $cb->( status [ 404, 'User not found' ], undef );
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

sub set_user_password ( $self, $user_id, $password, $cb ) {
    $self->get_user_by_id(
        $user_id,
        sub ( $status, $user ) {
            if ( !$status ) {
                $cb->($status);
            }
            else {
                $self->generate_user_password_hash(
                    $password,
                    $user_id,
                    sub ( $status, $hash ) {
                        if ( !$status ) {
                            $cb->($status);
                        }
                        else {
                            if ( $self->dbh->do( q[UPDATE api_user SET hash = ? WHERE id = ?], [ $hash, $user_id ] ) ) {
                                $cb->( status 200 );
                            }
                            else {
                                $cb->( status 500 );
                            }
                        }

                        return;
                    }
                );
            }

            return;
        }
    );

    return;
}

sub set_user_enabled ( $self, $user_id, $enabled, $cb ) {
    $self->get_user_by_id(
        $user_id,
        sub ( $status, $user ) {
            if ( !$status ) {
                $cb->($status);
            }
            else {
                if ( ( $enabled && !$user->{enabled} ) || ( !$enabled && $user->{enabled} ) ) {
                    $self->dbh->do( q[UPDATE api_user SET enabled = ? WHERE id = ?], [ $enabled, $user_id ] );

                    $cb->( status 200 );
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

# TODO
sub set_user_role ( $self, $user_id, $role_id, $cb ) {
    $self->get_role_by_id(
        $role_id,
        sub ( $status, $role ) {
            if ( !$status ) {
                $cb->($status);
            }
            else {
                if ( $self->dbh->do( q[UPDATE api_user SET role_id = ? WHERE id = ?], [ $role_id, $user_id ] ) ) {
                    $cb->( status 200 );
                }
                else {
                    $cb->( status [ 404, 'User not found' ] );
                }
            }

            return;
        }
    );

    return;
}

# USER TOKEN
# TODO, token roles can't be more, than user assigned roles, by default inherit all current user roles
sub create_user_token ( $self, $user_id, $role_id, $cb ) {
    $self->get_role_by_id(
        $role_id,
        sub ( $status, $role ) {

            # role not found
            if ( !$status ) {
                $cb->( $status, undef );
            }

            # role found
            else {
                $self->get_user_by_id(
                    $user_id,
                    sub ( $status, $user ) {

                        # user not found
                        if ( !$status ) {
                            $cb->( $status, undef );
                        }

                        # user found
                        else {
                            my $dbh = $self->dbh;

                            $dbh->begin_work;

                            if ( $dbh->do( q[INSERT INTO api_user_token (user_id, role_id, created_ts) VALUES (?, ?, ?)], [ $user_id, $role_id, time ] ) ) {
                                my $token_id = $dbh->last_insert_id;

                                $self->generate_user_token(
                                    $token_id,
                                    $user_id, $role_id,
                                    sub ( $status, $token, $hash ) {
                                        if ( !$status ) {
                                            $dbh->rollback;

                                            $cb->( status [ 500, 'User token creation error' ], undef );
                                        }
                                        else {
                                            if ( $dbh->do( q[UPDATE api_user_token SET hash = ? WHERE id = ?], [ $hash, $token_id ] ) ) {
                                                $dbh->commit;

                                                $cb->( status 201, $token );
                                            }
                                            else {
                                                $dbh->rollback;

                                                $cb->( status [ 500, 'User token creation error' ], undef );
                                            }
                                        }

                                        return;
                                    }
                                );
                            }

                            # token creation error
                            else {
                                $dbh->rollback;

                                $cb->( status [ 500, 'User token creation error' ], undef );
                            }
                        }

                        return;
                    }
                );
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
## |    3 | 102, 124, 149, 211,  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 282, 372, 405, 447,  |                                                                                                                |
## |      | 497, 510, 722, 747   |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 |                      | Subroutines::ProhibitUnusedPrivateSubroutines                                                                  |
## |      | 211                  | * Private subroutine/method '_create_app' declared but not used                                                |
## |      | 372                  | * Private subroutine/method '_create_app_instance' declared but not used                                       |
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
