package Pcore::App::API::Auth::Backend::Local::sqlite;

use Pcore -class;

with qw[Pcore::App::API::Auth::Backend::Local];

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
                `username` TEXT NOT NULL UNIQUE,
                `hash` BLOB,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `rid` INTEGER NULL REFERENCES `api_role` (`id`) ON DELETE RESTRICT
            );

            --- TOKEN
            CREATE TABLE IF NOT EXISTS `api_token` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `hash` BLOB UNIQUE,
                `uid` INTEGER NOT NULL REFERENCES `api_user` (`id`) ON DELETE CASCADE,
                `rid` INTEGER NOT NULL REFERENCES `api_role` (`id`) ON DELETE RESTRICT,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `temp` INTEGER NOT NULL DEFAULT 0
            );

            --- ROLE
            CREATE TABLE IF NOT EXISTS `api_role` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `rolename` TEXT NOT NULL UNIQUE,
                `desc` TEXT NOT NULL,
                `enabled` INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS `api_role_has_method` (
                `rid` INTEGER NOT NULL REFERENCES `api_role` (`id`) ON DELETE CASCADE,
                `mid` BLOB NOT NULL REFERENCES `api_method` (`id`) ON DELETE CASCADE
            );

            CREATE UNIQUE INDEX `idx_uniq_api_role_has_method` ON `api_role_has_method` (`rid`, `mid`);
SQL
    );

    $ddl->upgrade;

    $cb->( Pcore::Util::Status->new( { status => 200 } ) );

    return;
}

# APP
sub register_app_instance ( $self, $name, $desc, $version, $host, $handles, $cb ) {
    $self->dbh->do( 'INSERT OR IGNORE INTO api_app (name, desc, enabled) VALUES (?, ?, ?)', [ $name, $desc, 1 ] );

    my $app_id = $self->dbh->selectval( 'SELECT id FROM api_app WHERE name = ?', [$name] )->$*;

    $self->dbh->do( 'INSERT INTO api_app_instance (app_id, version, host, approved, enabled) VALUES (?, ?, ?, ?, ?)', [ $app_id, $version, $host, 0, 0 ] );

    my $app_instance_id = $self->dbh->last_insert_id;

    $cb->( Pcore::Util::Status->new( { status => 200 } ), $app_instance_id );

    return;
}

sub approve_app_instance ( $self, $app_instance_id, $cb ) {

    # generate token
    $self->create_token(
        $app_instance_id,
        $app_instance_id,
        sub ( $token, $hash ) {
            $self->dbh->do( 'UPDATE api_app_instance SET approved = 1, hash = ? WHERE id = ?', [ $hash, $app_instance_id ] );

            $cb->( Pcore::Util::Status->new( { status => 200 } ), $token );

            return;
        }
    );

    return;
}

# TODO set api methods
sub connect_app_instance ( $self, $app_instance_id, $app_instance_token, $cb ) {
    $cb->( Pcore::Util::Status->new( { status => 200 } ) );

    return;
}

# USER
sub get_user_by_id ( $self, $user_id, $cb ) {
    my $dbh = $self->dbh;

    if ( my $user = $dbh->selectrow( q[SELECT * FROM api_user WHERE id = ?], [$user_id] ) ) {
        $cb->( Pcore::Util::Status->new( { status => 200 } ), $user );
    }
    else {

        # user not found
        $cb->( Pcore::Util::Status->new( { status => 404 } ) );
    }

    return;
}

sub get_user_by_name ( $self, $username, $cb ) {
    my $dbh = $self->dbh;

    if ( my $user = $dbh->selectrow( q[SELECT * FROM api_user WHERE username = ?], [$username] ) ) {
        $cb->( Pcore::Util::Status->new( { status => 200 } ), $user );
    }
    else {

        # user not found
        $cb->( Pcore::Util::Status->new( { status => 404 } ) );
    }

    return;
}

sub create_user ( $self, $username, $password, $role_id, $cb ) {
    my $dbh = $self->dbh;

    $dbh->begin_work;

    if ( $dbh->do( q[INSERT OR IGNORE INTO api_user (username, role_id, enabled) VALUES (?, ?, ?)], [ $username, $role_id, 0 ] ) ) {
        my $user_id = $dbh->last_insert_id;

        $self->create_token(
            $user_id, $user_id,
            sub ( $token, $hash ) {
                $dbh->do( q[UPDATE api_user SET enabled = ?, hash = ? WHERE id = ?], [ 1, $hash, $user_id ] );

                $dbh->commit;

                # user created
                $cb->( Pcore::Util::Status->new( { status => 201 } ), $user_id, $password );

                return;
            }
        );
    }
    else {
        $dbh->rollback;

        # username already exists
        $cb->( Pcore::Util::Status->new( { status => 409 } ) );
    }

    return;
}

sub set_user_password ( $self, $user_id, $password, $cb ) {
    my $dbh = $self->dbh;

    if ( my $user = $dbh->selectrow( q[SELECT enabled FROM api_user WHERE id = ?], [$user_id] ) ) {

    }
    else {

        # user not found
        $cb->( Pcore::Util::Status->new( { status => 404 } ) );
    }

    return;
}

sub set_user_enabled ( $self, $user_id, $enabled, $cb ) {
    my $dbh = $self->dbh;

    if ( my $user = $dbh->selectrow( q[SELECT enabled FROM api_user WHERE id = ?], [$user_id] ) ) {
        if ( ( $enabled && !$user->{enabled} ) || ( !$enabled && $user->{enabled} ) ) {
            $dbh->do( q[UPDATE api_user SET enabled = ? WHERE id = ?], [ $enabled, $user_id ] );

            $cb->( Pcore::Util::Status->new( { status => 200 } ) );
        }
        else {

            # not modified
            $cb->( Pcore::Util::Status->new( { status => 304 } ) );
        }
    }
    else {

        # user not found
        $cb->( Pcore::Util::Status->new( { status => 404 } ) );
    }

    return;
}

sub set_user_role ( $self, $user_id, $role_id, $cb ) {
    return;
}

sub create_user_token ( $self, $user_id, $role_id, $cb ) {
    return;
}

# ROLE
sub create_role ( $self, $name, $desc, $cb ) {
    my $dbh = $self->dbh;

    if ( $dbh->do( q[INSERT OR IGNORE INTO api_user (name, desc, enabled) VALUES (?, ?, ?)], [ $name, $desc, 1 ] ) ) {
        my $role_id = $dbh->last_insert_id;

        $cb->( Pcore::Util::Status->new( { status => 201 } ), $role_id );
    }
    else {

        # role already exists
        $cb->( Pcore::Util::Status->new( { status => 409 } ) );
    }

    return;
}

sub set_role_enabled ( $self, $role_id, $enabled, $cb ) {
    my $dbh = $self->dbh;

    if ( my $role = $dbh->selectrow( q[SELECT enabled FROM api_role WHERE id = ?], [$role_id] ) ) {
        if ( ( $enabled && !$role->{enabled} ) || ( !$enabled && $role->{enabled} ) ) {
            $dbh->do( q[UPDATE api_role SET enabled = ? WHERE id = ?], [ $enabled, $role_id ] );

            $cb->( Pcore::Util::Status->new( { status => 200 } ) );
        }
        else {

            # not modified
            $cb->( Pcore::Util::Status->new( { status => 304 } ) );
        }
    }
    else {

        # role not found
        $cb->( Pcore::Util::Status->new( { status => 404 } ) );
    }

    return;
}

sub set_role_methods ( $self, $role_id, $methods, $cb ) {
    return;
}

sub add_role_methods ( $self, $role_id, $methods, $cb ) {
    return;
}

# TOKEN
sub set_token_enabled ( $self, $token_id, $enabled, $cb ) {
    return;
}

sub delete_token ( $self, $role_id, $cb ) {
    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 88, 121, 158, 229,   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 233                  |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 1                    | NamingConventions::Capitalization - Package "Pcore::App::API::Auth::Backend::Local::sqlite" does not start     |
## |      |                      | with a upper case letter                                                                                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Backend::Local::sqlite

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
