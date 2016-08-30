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
                `app_id` BLOB PRIMARY KEY NOT NULL,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `desc` TEXT NOT NULL,
                `hash` BLOB
            );

            CREATE TABLE IF NOT EXISTS `api_app_instance` (
                `instance_id` BLOB PRIMARY KEY NOT NULL,
                `app_id` NOT NULL REFERENCES `api_app` (`app_id`) ON DELETE RESTRICT,
                `version` BLOB NOT NULL,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `host` BLOB NOT NULL,
                `port` INTEGER NOT NULL
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

            CREATE UNIQ INDEX `idx_uniq_api_role_has_method` ON `api_role_has_method` (`rid`, `mid`);
SQL
    );

    $ddl->upgrade;

    $cb->( Pcore::Util::Status->new( { status => 200 } ) );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
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
