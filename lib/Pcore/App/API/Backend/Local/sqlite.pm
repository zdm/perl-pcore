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
                `created_ts` INTEGER,
                `approved` INTEGER NOT NULL DEFAULT 0,
                `approved_ts` INTEGER,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `last_connected_ts` INTEGER,
                `hash` BLOB
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
                `created_ts` INTEGER,
                `hash` BLOB,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `role_id` INTEGER NULL REFERENCES `api_role` (`id`) ON DELETE RESTRICT
            );

            --- USER TOKEN
            CREATE TABLE IF NOT EXISTS `api_user_token` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `created_ts` INTEGER,
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
sub auth_user_password ( $self, $user_name, $password, $cb ) {
    if ( my $user = $self->dbh->selectrow( q[SELECT id, hash FROM api_user WHERE name = ?], [$user_name] ) ) {
        $self->validate_user_password_hash( $password, $user->{hash}, $user->{id}, $cb );
    }
    else {
        $cb->( status 404 );
    }

    return;
}

# APP
sub get_app_by_id ( $self, $app_id, $cb ) {
    if ( my $app = $self->dbh->selectrow( q[SELECT * FROM api_app WHERE id = ?], [$app_id] ) ) {
        $cb->( status 200, $app );
    }
    else {
        $cb->( status [ 404, 'App not found' ], undef );
    }

    return;
}

sub create_app ( $self, $app_name, $desc, $cb ) {
    my $dbh = $self->dbh;

    # app created
    if ( $dbh->do( q[INSERT OR IGNORE INTO api_app (name, desc, enabled) VALUES (?, ?, ?)], [ $app_name, $desc, 1 ] ) ) {
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

sub create_app_instance ( $self, $app_id, $host, $cb ) {
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
                if ( $self->dbh->do( q[INSERT OR IGNORE INTO api_app_instance (app_id, host, created_ts) VALUES (?, ?, ?)], [ $app_id, $host, time ] ) ) {
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

sub approve_app_instance ( $self, $app_instance_id, $cb ) {
    $self->get_app_instance_by_id(
        $app_instance_id,
        sub ( $status, $app_instance ) {
            if ( !$status ) {
                $cb->( $status, undef );
            }
            else {
                if ( !$app_instance->{approved} ) {
                    $self->generate_app_instance_token(
                        $app_instance_id,
                        sub ( $status, $token, $hash ) {

                            # app instance token generation error
                            if ( !$status ) {
                                $cb->( $status, undef );
                            }

                            # app instance token generated
                            else {

                                # app instance approved
                                if ( $self->dbh->do( q[UPDATE api_app_instance SET approved = 1, approved_ts = ?, hash = ? WHERE id = ?], [ time, $hash, $app_instance_id ] ) ) {
                                    $cb->( status 200, $token );
                                }

                                # app instance approveal error
                                else {
                                    $cb->( status [ 500, 'App instance approval error' ], undef );
                                }
                            }

                            return;
                        }
                    );
                }
                else {

                    # app instance already approved
                    $cb->( status 304, undef );
                }
            }

            return;
        }
    );

    return;
}

sub connect_app_instance ( $self, $app_instance_id, $version, $cb ) {
    $self->get_app_instance_by_id(
        $app_instance_id,
        sub ( $status, $app_instance ) {
            if ( !$status ) {
                $cb->($status);
            }
            else {

                # connected
                if ( $self->dbh->do( q[UPDATE api_app_instance SET version = ?, last_connected_ts = ? WHERE id = ?], [ $version, time, $app_instance_id ] ) ) {
                    $cb->( status 200 );
                }

                # connection error
                else {
                    $cb->( status [ 500, 'App instance connection error' ] );
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

sub delete_app_instance ( $self, $app_instance_id, $cb ) {
    if ( $self->dbh->do( q[DELETE FROM api_app_instance WHERE id = ?], [$app_instance_id] ) ) {
        $cb->( status 200 );
    }
    else {
        $cb->( status [ 404, 'App instance not found' ] );
    }

    return;
}

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

sub create_role ( $self, $role_name, $desc, $cb ) {
    my $dbh = $self->dbh;

    # role created
    if ( $dbh->do( q[INSERT OR IGNORE INTO api_role (name, desc, enabled) VALUES (?, ?, ?)], [ $role_name, $desc, 1 ] ) ) {
        my $role_id = $dbh->last_insert_id;

        $cb->( status 201, $role_id );
    }

    # role creation error
    else {
        my $role_id = $dbh->selectval( 'SELECT id FROM api_role WHERE name = ?', [$role_name] )->$*;

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

sub get_user_by_name ( $self, $user_name, $cb ) {
    my $dbh = $self->dbh;

    if ( my $user = $dbh->selectrow( q[SELECT * FROM api_user WHERE name = ?], [$user_name] ) ) {
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

    # user alreasy exists
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

sub delete_user_token ( $self, $token_id, $cb ) {
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
## |    3 | 272, 299, 551, 575   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
