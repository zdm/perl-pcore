package Pcore::App::Auth::Backend::Local::pgsql;

use Pcore -class, -res, -sql;
use Pcore::Util::UUID qw[uuid_v4_str];

with qw[Pcore::App::Auth::Backend::Local];

sub _db_add_schema_patch ( $self, $dbh ) {
    $dbh->add_schema_patch(
        1, 'auth', <<"SQL"
            CREATE EXTENSION IF NOT EXISTS "pgcrypto";

            -- USER
            CREATE TABLE IF NOT EXISTS "auth_user" (
                "id" UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
                "name" TEXT NOT NULL UNIQUE,
                "hash" BYTEA NOT NULL,
                "enabled" BOOLEAN NOT NULL DEFAULT FALSE,
                "created" INT8 NOT NULL DEFAULT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP)
            );

            -- PERMISSIONS
            CREATE TABLE IF NOT EXISTS "auth_permission" (
                "id" UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
                "name" TEXT NOT NULL UNIQUE
            );

            -- USER PERMISSION
            CREATE TABLE IF NOT EXISTS "auth_user_permission" (
                "id" UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
                "user_id" UUID NOT NULL REFERENCES "auth_user" ("id") ON DELETE CASCADE, -- remove permission assoc., on user delete
                "permission_id" UUID NOT NULL REFERENCES "auth_permission" ("id") ON DELETE RESTRICT -- prevent deleting permission, if has assigned users
            );

            CREATE UNIQUE INDEX IF NOT EXISTS "idx_uniq_auth_user_permission" ON "auth_user_permission" ("user_id", "permission_id");

            -- USER TOKEN
            CREATE TABLE IF NOT EXISTS "auth_user_token" (
                "id" UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
                "type" INT2 NOT NULL,
                "user_id" UUID NOT NULL REFERENCES "auth_user" ("id") ON DELETE CASCADE,
                "hash" BYTEA NOT NULL,
                "desc" TEXT,
                "created" INT8 NOT NULL DEFAULT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP)
            );

            -- USER TOKEN PERMISSION
            CREATE TABLE IF NOT EXISTS "auth_user_token_permission" (
                "id" UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
                "user_token_id" UUID NOT NULL REFERENCES "auth_user_token" ("id") ON DELETE CASCADE,
                "user_permission_id" UUID NOT NULL REFERENCES "auth_user_permission" ("id") ON DELETE CASCADE
            );

            CREATE UNIQUE INDEX IF NOT EXISTS "idx_uniq_auth_user_token_permission" ON "auth_user_token_permission" ("user_token_id", "user_permission_id");
SQL
    );

    return;
}

sub _db_add_permissions ( $self, $dbh, $permissions ) {
    return $dbh->do( [ q[INSERT INTO "auth_permission"], VALUES [ map { { name => $_ } } $permissions->@* ], 'ON CONFLICT DO NOTHING' ] );
}

sub _db_create_user ( $self, $dbh, $user_name, $hash, $enabled ) {
    my $user_id = uuid_v4_str;

    state $q1 = $dbh->prepare('INSERT INTO "auth_user" ("id", "name", "hash", "enabled") VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING');

    my $res = $dbh->do( $q1, [ SQL_UUID $user_id, SQL_UUID $user_name, SQL_BYTEA $hash, SQL_BOOL $enabled ] );

    if ( !$res->{rows} ) {
        return res 500;
    }
    else {
        return res 200, { id => $user_id };
    }
}

sub _db_set_user_permissions ( $self, $dbh, $user_id, $permissions_ids ) {
    my $res = $dbh->do( [ 'INSERT INTO "auth_user_permission"', VALUES [ map { { permission_id => SQL_UUID $_, user_id => SQL_UUID $user_id } } $permissions_ids->@* ], 'ON CONFLICT DO NOTHING' ] );

    return res 500 if !$res;

    my $modified = $res->{rows};

    # remove permissions
    $res = $dbh->do( [ 'DELETE FROM "auth_user_permission" WHERE "user_id" =', SQL_UUID $user_id, 'AND "permission_id" NOT', IN $permissions_ids ] );

    if ( !$res ) {
        return res 500;
    }
    else {
        $modified += $res->{rows};

        if ($modified) {
            return res 200, { user_id => $user_id };
        }
        else {
            return res 204;
        }
    }
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
## |      | 61                   | * Private subroutine/method '_db_add_permissions' declared but not used                                        |
## |      | 65                   | * Private subroutine/method '_db_create_user' declared but not used                                            |
## |      | 80                   | * Private subroutine/method '_db_set_user_permissions' declared but not used                                   |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 65, 80               | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
