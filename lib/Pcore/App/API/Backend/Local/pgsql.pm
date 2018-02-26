package Pcore::App::API::Backend::Local::pgsql;

use Pcore -class, -result;

with qw[Pcore::App::API::Backend::Local::pgsql::App];
with qw[Pcore::App::API::Backend::Local::pgsql::AppInstance];
with qw[Pcore::App::API::Backend::Local::pgsql::User];
with qw[Pcore::App::API::Backend::Local::pgsql::UserToken];
with qw[Pcore::App::API::Backend::Local::pgsql::UserSession];

with qw[Pcore::App::API::Backend::Local];

# INIT DB
sub init_db ( $self, $cb ) {

    # create db
    my $dbh = $self->dbh;

    $dbh->add_schema_patch(
        1 => <<"SQL"
            CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

            --- APP
            CREATE TABLE IF NOT EXISTS "api_app" (
                "id" UUID PRIMARY KEY NOT NULL,
                "name" TEXT NOT NULL UNIQUE,
                "desc" TEXT NOT NULL,
                "created_ts" INT8 NOT NULL
            );

            --- APP INSTANCE
            CREATE TABLE IF NOT EXISTS "api_app_instance" (
                "id" UUID PRIMARY KEY NOT NULL,
                "app_id" UUID NOT NULL REFERENCES "api_app" ("id") ON DELETE RESTRICT,
                "version" TEXT NOT NULL,
                "host" TEXT NOT NULL,
                "created_ts" INT8 NOT NULL,
                "last_connected_ts" INT8,
                "hash" TEXT NOT NULL
            );

            --- APP ROLE
            CREATE TABLE IF NOT EXISTS "api_app_role" (
                "id" UUID PRIMARY KEY NOT NULL,
                "app_id" UUID NOT NULL REFERENCES "api_app" ("id") ON DELETE CASCADE,
                "name" TEXT NOT NULL,
                "desc" TEXT NOT NULL
            );

            CREATE UNIQUE INDEX IF NOT EXISTS "idx_uniq_api_app_role_app_id_name" ON "api_app_role" ("app_id", "name");

            --- APP PERMISSION
            CREATE TABLE IF NOT EXISTS "api_app_permission" (
                "id" UUID PRIMARY KEY NOT NULL,
                "app_id" UUID NOT NULL REFERENCES "api_app" ("id") ON DELETE CASCADE, --- remove role assoc., on app delete
                "app_role_id" UUID NOT NULL REFERENCES "api_app_role" ("id") ON DELETE RESTRICT, --- prevent deleting role, if has assigned apps
                "approved" INT2 NOT NULL DEFAULT 0
            );

            CREATE UNIQUE INDEX IF NOT EXISTS "idx_uniq_api_app_permission" ON "api_app_permission" ("app_id", "app_role_id");

            --- USER
            CREATE TABLE IF NOT EXISTS "api_user" (
                "id" UUID PRIMARY KEY NOT NULL,
                "name" TEXT NOT NULL UNIQUE,
                "created_ts" INT8,
                "enabled" INT8 NOT NULL DEFAULT 0,
                "hash" TEXT NOT NULL
            );

            --- USER PERMISSION
            CREATE TABLE IF NOT EXISTS "api_user_permission" (
                "id" UUID PRIMARY KEY NOT NULL,
                "user_id" UUID NOT NULL REFERENCES "api_user" ("id") ON DELETE CASCADE, --- remove role assoc., on user delete
                "app_role_id" UUID NOT NULL REFERENCES "api_app_role" ("id") ON DELETE RESTRICT --- prevent deleting role, if has assigned users
            );

            CREATE UNIQUE INDEX IF NOT EXISTS "idx_uniq_api_user_permission" ON "api_user_permission" ("user_id", "app_role_id");

            --- USER TOKEN
            CREATE TABLE IF NOT EXISTS "api_user_token" (
                "id" UUID PRIMARY KEY NOT NULL, --- UUID hex
                "user_id" UUID NOT NULL REFERENCES "api_user" ("id") ON DELETE CASCADE,
                "desc" TEXT,
                "created_ts" INT8,
                "hash" TEXT NOT NULL
            );

            --- USER TOKEN PERMISSION
            CREATE TABLE IF NOT EXISTS "api_user_token_permission" (
                "id" UUID PRIMARY KEY NOT NULL,
                "user_token_id" UUID NOT NULL REFERENCES "api_user_token" ("id") ON DELETE CASCADE,
                "user_permission_id" UUID NOT NULL REFERENCES "api_user_permission" ("id") ON DELETE CASCADE
            );

            CREATE UNIQUE INDEX IF NOT EXISTS "idx_uniq_api_user_token_permission" ON "api_user_token_permission" ("user_token_id", "user_permission_id");

            --- USER SESSION
            CREATE TABLE IF NOT EXISTS "api_user_session" (
                "id" UUID PRIMARY KEY NOT NULL, --- UUID hex
                "user_id" UUID NOT NULL REFERENCES "api_user" ("id") ON DELETE CASCADE,
                "created_ts" INT8,
                "hash" TEXT NOT NULL
            );
SQL
    );

    $dbh->upgrade_schema( sub ($status) {
        die $status if !$status;

        $cb->($status);

        return;
    } );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::pgsql

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
