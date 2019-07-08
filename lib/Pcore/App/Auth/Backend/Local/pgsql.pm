package Pcore::App::Auth::Backend::Local::pgsql;

use Pcore -class, -res, -sql;
use Pcore::App::Auth qw[:ALL];

with qw[Pcore::App::Auth::Backend::Local];

sub _db_add_schema_patch ( $self, $dbh ) {
    $dbh->add_schema_patch(
        1, 'auth', <<"SQL"
            CREATE EXTENSION IF NOT EXISTS "pgcrypto";

            -- PERMISSIONS
            CREATE TABLE IF NOT EXISTS "auth_app_permission" (
                "id" SERIAL2 PRIMARY KEY NOT NULL,
                "name" TEXT NOT NULL UNIQUE,
                "enabled" BOOL NOT NULL DEFAULT TRUE
            );

            -- USER
            CREATE SEQUENCE IF NOT EXISTS "auth_user_id_seq" AS INT4 INCREMENT BY 1 START 100;

            CREATE TABLE IF NOT EXISTS "auth_user" (
                "id" INT4 PRIMARY KEY NOT NULL DEFAULT NEXTVAL('auth_user_id_seq'),
                "created" INT8 NOT NULL DEFAULT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP),
                "name" TEXT NOT NULL UNIQUE,
                "hash" BYTEA,
                "enabled" BOOLEAN NOT NULL DEFAULT TRUE
            );

            -- USER PERMISSIONS
            CREATE TABLE IF NOT EXISTS "auth_user_permission" (
                "user_id" INT4 NOT NULL REFERENCES "auth_user" ("id") ON DELETE CASCADE,
                "permission_id" INT2 NOT NULL REFERENCES "auth_app_permission" ("id") ON DELETE CASCADE,
                "enabled" BOOL NOT NULL DEFAULT TRUE,
                PRIMARY KEY ("user_id", "permission_id")
            );

            -- TOKEN
            CREATE TABLE IF NOT EXISTS "auth_token" (
                "id" UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
                "created" INT8 NOT NULL DEFAULT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP),
                "name" TEXT,
                "user_id" INT4 NOT NULL REFERENCES "auth_user" ("id") ON DELETE CASCADE,
                "hash" BYTEA NOT NULL,
                "enabled" BOOL NOT NULL DEFAULT TRUE
            );

            -- TOKEN PERMISSIONS
            CREATE TABLE IF NOT EXISTS "auth_token_permission" (
                "token_id" UUID NOT NULL,
                "user_id" INT4 NOT NULL,
                "permission_id" INT2 NOT NULL,
                "enabled" BOOL NOT NULL DEFAULT TRUE,
                PRIMARY KEY ("token_id", "permission_id"),
                FOREIGN KEY ("user_id", "permission_id") REFERENCES "auth_user_permission" ("user_id", "permission_id") ON DELETE CASCADE,
                FOREIGN KEY ("permission_id") REFERENCES "auth_app_permission" ("id") ON DELETE CASCADE
            );

            -- SESSION
            CREATE TABLE IF NOT EXISTS "auth_session" (
                "id" UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
                "created" INT8 NOT NULL DEFAULT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP),
                "user_id" INT4 NOT NULL REFERENCES "auth_user" ("id") ON DELETE CASCADE,
                "hash" BYTEA NOT NULL
            );
SQL
    );

    return;
}

sub _db_insert_user ( $self, $dbh, $user_name ) {
    my $res;

    if ( $self->user_is_root($user_name) ) {
        state $q1 = $dbh->prepare(q[INSERT INTO "auth_user" ("id", "name", "enabled") VALUES (?, ?, FALSE) ON CONFLICT DO NOTHING RETURNING "id"]);

        # insert user
        $res = $dbh->selectrow( $q1, [ $ROOT_USER_ID, $user_name ] );
    }
    else {
        state $q1 = $dbh->prepare(q[INSERT INTO "auth_user" ("name", "enabled") VALUES (?, FALSE) ON CONFLICT DO NOTHING RETURNING "id"]);

        # insert user
        $res = $dbh->selectrow( $q1, [$user_name] );
    }

    # DBH error
    return $res if !$res;

    # username already exists
    return res [ 400, 'Username is already exists' ] if !$res->{data};

    return $res;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 |                      | Subroutines::ProhibitUnusedPrivateSubroutines                                                                  |
## |      | 8                    | * Private subroutine/method '_db_add_schema_patch' declared but not used                                       |
## |      | 73                   | * Private subroutine/method '_db_insert_user' declared but not used                                            |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::Auth::Backend::Local::pgsql

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
