package Pcore::App::API::Backend::Local::sqlite;

use Pcore -class;
use Pcore::Util::Status::Keyword qw[status];

with qw[Pcore::App::API::Backend::Local];

# INIT AUTH BACKEND
sub init ( $self, $cb ) {

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
                `enabled` INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS `api_app_instance` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `app_id` NOT NULL REFERENCES `api_app` (`id`) ON DELETE RESTRICT,
                `version` BLOB NOT NULL,
                `host` BLOB NOT NULL,
                `approved` INTEGER NOT NULL DEFAULT 0,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `hash` BLOB,
                `role_id` INTEGER NULL REFERENCES `api_role` (`id`) ON DELETE RESTRICT
            );

            --- METHOD
            CREATE TABLE IF NOT EXISTS `api_method` (
                `id` BLOB PRIMARY KEY NOT NULL,
                `app_id` BLOB NOT NULL,
                `version` BLOB NOT NULL,
                `class` BLOB NOT NULL,
                `name` BLOB NOT NULL,
                `desc` TEXT NOT NULL
            );

            --- USER
            CREATE TABLE IF NOT EXISTS `api_user` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `name` TEXT NOT NULL UNIQUE,
                `hash` BLOB,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `role_id` INTEGER NULL REFERENCES `api_role` (`id`) ON DELETE RESTRICT
            );

            --- USER TOKEN
            CREATE TABLE IF NOT EXISTS `api_user_token` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `user_id` INTEGER NOT NULL REFERENCES `api_user` (`id`) ON DELETE CASCADE,
                `role_id` INTEGER NOT NULL REFERENCES `api_role` (`id`) ON DELETE RESTRICT,
                `hash` BLOB UNIQUE
            );

            --- ROLE
            CREATE TABLE IF NOT EXISTS `api_role` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `name` TEXT NOT NULL UNIQUE,
                `desc` TEXT NOT NULL,
                `enabled` INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS `api_role_has_method` (
                `role_id` INTEGER NOT NULL REFERENCES `api_role` (`id`) ON DELETE CASCADE,
                `method_id` BLOB NOT NULL REFERENCES `api_method` (`id`) ON DELETE CASCADE
            );

            CREATE UNIQUE INDEX `idx_uniq_api_role_has_method` ON `api_role_has_method` (`role_id`, `method_id`);
SQL
    );

    $ddl->upgrade;

    $cb->( status 200 );

    return;
}

# AUTH
sub auth_user_password ( $self, $name, $password, $cb ) {
    if ( my $user = $self->dbh->selectrow( q[SELECT id, hash FROM api_user WHERE name = ?], [$name] ) ) {
        $self->validate_user_password_hash( $password, $user->{hash}, $user->{id}, $cb );
    }
    else {
        $cb->( status 404 );
    }

    return;
}

# APP
sub get_app_by_id ( $self, $app_id, $cb ) {
    if ( my $app = $self->dbh->selectrow( q[SELECT * FROM app_role WHERE id = ?], [$app_id] ) ) {
        $cb->( status 200, $app );
    }
    else {
        $cb->( status [ 404, 'App not found' ], undef );
    }

    return;
}

sub create_app ( $self, $name, $desc, $cb ) {
    my $dbh = $self->dbh;

    if ( $dbh->do( q[INSERT OR IGNORE INTO api_app (name, desc, enabled) VALUES (?, ?, ?)], [ $name, $desc, 1 ] ) ) {
        my $app_id = $dbh->last_insert_id;

        $cb->( status 201, $app_id );
    }
    else {
        my $app_id = $dbh->selectval( 'SELECT id FROM api_app WHERE name = ?', [$name] )->$*;

        # role already exists
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

sub delete_app ( $self, $app_id, $cb ) {
    if ( $self->dbh->do( q[DELETE FROM api_app WHERE id = ?], [$app_id] ) ) {
        $cb->( status 200 );
    }
    else {
        $cb->( status [ 404, 'App not found' ] );
    }

    return;
}

# APP INSTANCE

# ROLE
sub get_role_by_id ( $self, $role_id, $cb ) {
    if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_role WHERE id = ?], [$role_id] ) ) {
        $cb->( status 200, $role );
    }
    else {
        $cb->( status [ 404, 'Role not found' ], undef );
    }

    return;
}

sub create_role ( $self, $name, $desc, $cb ) {
    my $dbh = $self->dbh;

    if ( $dbh->do( q[INSERT OR IGNORE INTO api_role (name, desc, enabled) VALUES (?, ?, ?)], [ $name, $desc, 1 ] ) ) {
        my $role_id = $dbh->last_insert_id;

        $cb->( status 201, $role_id );
    }
    else {
        my $role_id = $dbh->selectval( 'SELECT id FROM api_role WHERE name = ?', [$name] )->$*;

        # role already exists
        $cb->( status [ 409, 'Role already exists' ], $role_id );
    }

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
                    $self->dbh->do( q[UPDATE api_role SET enabled = ? WHERE id = ?], [ $enabled, $role_id ] );

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

# USER
sub get_user_by_id ( $self, $user_id, $cb ) {
    my $dbh = $self->dbh;

    if ( my $user = $dbh->selectrow( q[SELECT * FROM api_user WHERE id = ?], [$user_id] ) ) {
        delete $user->{hash};

        $cb->( status 200, $user );
    }
    else {

        # user not found
        $cb->( status [ 404, 'User not found' ], undef );
    }

    return;
}

sub get_user_by_name ( $self, $name, $cb ) {
    my $dbh = $self->dbh;

    if ( my $user = $dbh->selectrow( q[SELECT * FROM api_user WHERE name = ?], [$name] ) ) {
        delete $user->{hash};

        $cb->( status 200, $user );
    }
    else {

        # user not found
        $cb->( status [ 404, 'User not found' ], undef );
    }

    return;
}

sub create_user ( $self, $name, $password, $cb ) {
    my $dbh = $self->dbh;

    $dbh->begin_work;

    # user created
    if ( $dbh->do( q[INSERT OR IGNORE INTO api_user (name, enabled) VALUES (?, ?)], [ $name, 0 ] ) ) {
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

    # user alreasy exists
    else {
        $dbh->rollback;

        my $user_id = $dbh->selectval( 'SELECT id FROM api_user WHERE name = ?', [$name] )->$*;

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

                            if ( $dbh->do( q[INSERT INTO api_user_token (user_id, role_id) VALUES (?, ?)], [ $user_id, $role_id ] ) ) {
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

sub delete_user_token ( $self, $token_id, $cb ) {
    if ( $self->dbh->do( q[DELETE FROM api_user_token WHERE id = ?], [$token_id] ) ) {
        $cb->( status 200 );
    }
    else {
        $cb->( status [ 404, 'User token not found' ] );
    }

    return;
}

# ============================================

# APP INSTANCE
sub register_app_instance ( $self, $name, $desc, $version, $host, $handles, $cb ) {
    $self->dbh->do( 'INSERT OR IGNORE INTO api_app (name, desc, enabled) VALUES (?, ?, ?)', [ $name, $desc, 1 ] );

    my $app_id = $self->dbh->selectval( 'SELECT id FROM api_app WHERE name = ?', [$name] )->$*;

    $self->dbh->do( 'INSERT INTO api_app_instance (app_id, version, host, approved, enabled) VALUES (?, ?, ?, ?, ?)', [ $app_id, $version, $host, 0, 0 ] );

    my $app_instance_id = $self->dbh->last_insert_id;

    $cb->( status 200, $app_instance_id );

    return;
}

sub approve_app_instance ( $self, $app_instance_id, $cb ) {

    # generate token
    $self->generate_app_instance_token(
        $app_instance_id,
        sub ( $status, $token, $hash ) {
            if ( !$status ) {
                $cb->( $status, undef );
            }
            else {
                if ( $self->dbh->do( 'UPDATE api_app_instance SET approved = 1, hash = ? WHERE id = ?', [ $hash, $app_instance_id ] ) ) {
                    $cb->( status 200, $token );
                }
                else {
                    $cb->( status 500, undef );
                }
            }

            return;
        }
    );

    return;
}

# TODO set api methods
sub connect_app_instance ( $self, $app_instance_id, $app_instance_token, $cb ) {
    $cb->( status 200 );

    return;
}

sub get_app_instance_by_id ( $self, $app_instance_id, $cb ) {
    my $dbh = $self->dbh;

    if ( my $app_instance = $dbh->selectrow( q[SELECT * FROM api_app_instance WHERE id = ?], [$app_instance_id] ) ) {
        $cb->( status 200, $app_instance );
    }
    else {
        $cb->( status 404, undef );
    }

    return;
}

sub set_app_instance_enabled ( $self, $app_instance_id, $enabled, $cb ) {
    my $dbh = $self->dbh;

    if ( my $app_instance = $dbh->selectrow( q[SELECT enabled FROM api_app_instance WHERE id = ?], [$app_instance_id] ) ) {
        if ( ( $enabled && !$app_instance->{enabled} ) || ( !$enabled && $app_instance->{enabled} ) ) {
            $dbh->do( q[UPDATE api_app_instance SET enabled = ? WHERE id = ?], [ $enabled, $app_instance_id ] );

            $cb->( status 200 );
        }
        else {

            # not modified
            $cb->( status 304 );
        }
    }
    else {

        # app instance not found
        $cb->( status 404 );
    }

    return;
}

sub remove_app_instance ( $self, $app_instance_id, $cb ) {
    ...;

    return;
}

# ROLE
sub set_role_methods ( $self, $role_id, $methods, $cb ) {
    return;
}

sub add_role_methods ( $self, $role_id, $methods, $cb ) {
    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 381, 405, 496, 536,  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 555                  |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 580                  | ControlStructures::ProhibitYadaOperator - yada operator (...) used                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 1                    | NamingConventions::Capitalization - Package "Pcore::App::API::Backend::Local::sqlite" does not start with a    |
## |      |                      | upper case letter                                                                                              |
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
