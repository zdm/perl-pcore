package Pcore::App::Auth::Backend::Local::sqlite;

use Pcore -class, -res, -sql;
use Pcore::Util::UUID qw[uuid_v4_str];

with qw[Pcore::App::Auth::Backend::Local];

sub _db_add_schema_patch ( $self, $dbh ) {
    $dbh->add_schema_patch(
        1, 'auth', <<"SQL"

            -- USER
            CREATE TABLE IF NOT EXISTS "auth_user" (
                "id" BLOB PRIMARY KEY NOT NULL DEFAULT(CAST(uuid_generate_v4() AS BLOB)),
                "name" TEXT NOT NULL UNIQUE,
                "hash" BLOB NOT NULL,
                "enabled" INTEGER NOT NULL DEFAULT 0,
                "created" INTEGER NOT NULL DEFAULT(STRFTIME('%s', 'NOW'))
            );

            -- PERMISSION
            CREATE TABLE IF NOT EXISTS "auth_permission" (
                "id" BLOB PRIMARY KEY NOT NULL DEFAULT(CAST(uuid_generate_v4() AS BLOB)),
                "name" BLOB NOT NULL UNIQUE
            );

            -- USER PERMISSION
            CREATE TABLE IF NOT EXISTS "auth_user_permission" (
                "id" BLOB PRIMARY KEY NOT NULL DEFAULT(CAST(uuid_generate_v4() AS BLOB)),
                "user_id" BLOB NOT NULL REFERENCES "auth_user" ("id") ON DELETE CASCADE, -- remove permission assoc., on user delete
                "permission_id" BLOB NOT NULL REFERENCES "auth_permission" ("id") ON DELETE RESTRICT -- prevent deleting permission, if has assigned users
            );

            CREATE UNIQUE INDEX IF NOT EXISTS "idx_uniq_auth_user_permission" ON "auth_user_permission" ("user_id", "permission_id");

            -- USER TOKEN
            CREATE TABLE IF NOT EXISTS "auth_user_token" (
                "id" BLOB PRIMARY KEY NOT NULL DEFAULT(CAST(uuid_generate_v4() AS BLOB)),
                "type" INTEGER NOT NULL,
                "user_id" BLOB NOT NULL REFERENCES "auth_user" ("id") ON DELETE CASCADE,
                "hash" BLOB NOT NULL,
                "desc" TEXT,
                "created" INTEGER NOT NULL DEFAULT(STRFTIME('%s', 'NOW'))
            );

            -- USER TOKEN PERMISSION
            CREATE TABLE IF NOT EXISTS "auth_user_token_permission" (
                "id" BLOB PRIMARY KEY NOT NULL DEFAULT(CAST(uuid_generate_v4() AS BLOB)),
                "user_token_id" BLOB NOT NULL REFERENCES "auth_user_token" ("id") ON DELETE CASCADE,
                "user_permission_id" BLOB NOT NULL REFERENCES "auth_user_permission" ("id") ON DELETE CASCADE
            );

            CREATE UNIQUE INDEX IF NOT EXISTS "idx_uniq_auth_user_token_permission" ON "auth_user_token_permission" ("user_token_id", "user_permission_id");
SQL
    );

    return;
}

# TODO
sub _db_sync_app_permissions ( $self, $dbh, $permissions ) {
    return $dbh->do( [ q[INSERT OR IGNORE INTO "auth_permission"], VALUES [ map { { name => $_ } } $permissions->@* ] ] );
}

sub _db_create_user ( $self, $dbh, $user_name, $hash, $enabled ) {
    my $user_id = uuid_v4_str;

    state $q1 = $dbh->prepare('INSERT OR IGNORE INTO "auth_user" ("id", "name", "hash", "enabled") VALUES (?, ?, ?, ?)');

    my $res = $dbh->do( $q1, [ SQL_UUID $user_id, $user_name, SQL_BYTEA $hash, SQL_BOOL $enabled ] );

    if ( !$res->{rows} ) {
        return res 500;
    }
    else {
        return res 200, { id => $user_id };
    }
}

sub _db_set_user_permissions ( $self, $dbh, $user_id, $permissions_ids ) {
    my $res = $dbh->do( [ 'INSERT OR IGNORE INTO "auth_user_permission"', VALUES [ map { { permission_id => SQL_UUID $_, user_id => SQL_UUID $user_id } } $permissions_ids->@* ] ] );

    return res 500 if !$res;

    my $modified = $res->{rows};

    # remove permissions
    $res = $dbh->do( [ 'DELETE FROM "auth_user_permission" WHERE "user_id" =', SQL_UUID $user_id, 'AND "permission_id" NOT', IN [ map { SQL_UUID $_} $permissions_ids->@* ] ] );

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
## |      | 61                   | * Private subroutine/method '_db_sync_app_permissions' declared but not used                                   |
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

Pcore::App::Auth::Backend::Local::sqlite

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
