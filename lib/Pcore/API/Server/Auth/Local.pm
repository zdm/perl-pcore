package Pcore::API::Server::Auth::Local;

use Pcore -class;
use Pcore::API::Server::RPC::Hash;
use Pcore::Util::Hash::RandKey;

with qw[Pcore::API::Server::Auth];

has dbh         => ( is => 'lazy', isa => ConsumerOf ['Pcore::DBH'],                 init_arg => undef );
has _hash_rpc   => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::PM::RPC'],       init_arg => undef );
has _hash_cache => ( is => 'ro',   isa => InstanceOf ['Pcore::Util::Hash::RandKey'], default  => sub { Pcore::Util::Hash::RandKey->new }, init_arg => undef );

sub _build_dbh ($self) {
    my $dbh = P->handle('sqlite:auth.sqlite');

    # create db
    my $ddl = $dbh->ddl;

    $ddl->add_changeset(
        id  => 1,
        sql => <<"SQL"
            CREATE TABLE IF NOT EXISTS `api_user` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `username` TEXT NOT NULL UNIQUE,
                `password` BLOB NOT NULL,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `api_role` INTEGER NOT NULL REFERENCES `api_role` (`id`) ON DELETE RESTRICT
            );

            CREATE TABLE IF NOT EXISTS `api_token` (
                `id` BLOB PRIMARY KEY NOT NULL,
                `token` BLOB NOT NULL,
                `uid` INTEGER NOT NULL REFERENCES `api_user` (`id`) ON DELETE CASCADE,
                `enabled` INTEGER NOT NULL DEFAULT 0,
                `api_role` INTEGER NOT NULL REFERENCES `api_role` (`id`) ON DELETE RESTRICT
            );

            CREATE TABLE IF NOT EXISTS `api_role` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `name` TEXT NOT NULL,
                `desc` TEXT NOT NULL,
                `enabled` INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS `api_method` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `app_id` TEXT NOT NULL,
                `api_version` INTEGER NOT NULL,
                `api_class` INTEGER NOT NULL,
                `api_method` INTEGER NOT NULL,
                `desc` TEXT NOT NULL
            );

            CREATE UNIQUE INDEX IF NOT EXISTS `api_method_uniq_idx` ON `api_method` (`app_id`, `api_version`, `api_class`, `api_method`);

            CREATE TABLE IF NOT EXISTS `api_role_has_method` (
                `api_role_id` INTEGER NOT NULL REFERENCES `api_role` (`id`) ON DELETE CASCADE,
                `api_method_id` INTEGER NOT NULL REFERENCES `api_method` (`id`) ON DELETE CASCADE
            );
SQL
    );

    $ddl->upgrade;

    return $dbh;
}

sub _build__hash_rpc($self) {
    return P->pm->run_rpc(
        'Pcore::API::Server::RPC::Hash',
        workers   => 1,
        buildargs => {
            scrypt_N   => 16_384,
            scrypt_r   => 8,
            scrypt_p   => 1,
            scrypt_len => 32,
        },
    );
}

# TODO return authenticated api object on success
sub auth_password ( $self, $username, $password, $cb ) {
    state $q1 = $self->dbh->query('SELECT * FROM api_user WHERE username = ?');

    if ( my $user = $q1->selectrow( [$username] ) ) {
        $self->_verify_hash(
            $password,
            $user->{password},
            sub ($match) {
                if ($match) {
                    $cb->( $user->{id} );
                }
                else {
                    $cb->(undef);
                }

                return;
            }
        );
    }
    else {
        $cb->(undef);
    }

    return;
}

# TODO check b64 decode and length
# TODO return authenticated api object on success
sub auth_token ( $self, $token_b64, $cb ) {
    state $q1 = $self->dbh->query('SELECT * FROM api_token WHERE id = ?');

    # TODO check, that decoded
    my $token_raw = P->data->from_b64_url($token_b64);

    my $token_id = substr $token_raw, 0, 16, q[];

    if ( my $token = $q1->selectrow( [$token_id] ) ) {
        $self->_verify_hash(
            $token_raw,
            $token->{token},
            sub ($match) {
                if ($match) {
                    $cb->( $token->{uid} );
                }
                else {
                    $cb->(undef);
                }

                return;
            }
        );
    }
    else {
        $cb->(undef);
    }

    return;
}

# TODO - create user with uid = 1 if not exitst, return new password
sub set_root_password ( $self, $password = undef ) {
    return;
}

# TODO update api methods in database, or upload api map to cluster
sub update_api_map ($self) {
    return;
}

# TODO implement cache size
sub _verify_hash ( $self, $str, $hash, $cb ) {
    $str = P->text->encode_utf8($str);

    my $id = $str . $hash;

    if ( exists $self->{_hash_cache}->{$id} ) {
        $cb->(1);
    }
    else {
        $self->_hash_rpc->rpc_call(
            'verify_scrypt',
            [ $str, $hash ],
            sub ($match) {
                $self->{_hash_cache}->{$id} = undef;

                $cb->($match);

                return;
            }
        );
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Server::Auth::Local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
