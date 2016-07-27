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
                `api_role` INTEGER NULL REFERENCES `api_role` (`id`) ON DELETE RESTRICT
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
                `app_id` BLOB NOT NULL,
                `method_id` BLOB NOT NULL UNIQUE,
                `desc` TEXT NOT NULL
            );

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
sub set_root_password ( $self, $password ) {
    my $blocking_cv = AE::cv;

    $password //= P->random->bytes_hex(32);

    state $q1 = $self->dbh->query('SELECT id FROM api_user WHERE id = 1');

    state $q2 = $self->dbh->query(q[INSERT INTO api_user (id, username, password, enabled) VALUES (1, 'root', ?, 1)]);

    state $q3 = $self->dbh->query('UPDATE api_user SET password = ? WHERE id = 1');

    $q2->do( [$password] ) if !$q1->selectall_arrayref;

    $self->_hash_rpc->rpc_call(
        'create_scrypt',
        [$password],
        sub ($password_hash) {
            $q3->do( [$password_hash] );

            $blocking_cv->send($password);

            return;
        }
    );

    return $blocking_cv->recv;
}

# TODO update api methods in database, or upload api map to cluster
sub upload_api_map ( $self, $map ) {
    my $remote_methods = $self->dbh->selectall_hashref( 'SELECT * FROM api_method', key_cols => 'method_id' );

    my ( $add_methods, $remove_methods, $update_methods );

    for my $method_path ( keys $map->%* ) {
        if ( !exists $remote_methods->{$method_path} ) {
            $add_methods->{$method_path} = $map->{$method_path};
        }
        else {
            if ( $remote_methods->{$method_path}->{desc} ne $map->{$method_path}->{desc} ) {
                $update_methods->{$method_path} = $map->{$method_path};
            }
        }
    }

    for my $method_path ( keys $remote_methods->%* ) {
        if ( !exists $map->{$method_path} ) {
            $remove_methods->{$method_path} = undef;
        }
    }

    if ($add_methods) {
        my $q1 = $self->dbh->query('INSERT INTO api_method (app_id, method_id, desc) VALUES (?, ?, ?)');

        for my $method ( values $add_methods->%* ) {
            $q1->do( [ '_', $method->{id}, $method->{desc} ] );
        }
    }

    if ($update_methods) {
        my $q1 = $self->dbh->query('UPDATE api_method SET desc = ? WHERE method_id = ?');

        for my $method ( values $update_methods->%* ) {
            $q1->do( [ $method->{desc}, $method->{id} ] );
        }
    }

    if ($remove_methods) {
        my $q1 = $self->dbh->query('DELETE FROM api_method WHERE method_id = ?');

        for my $method ( keys $remove_methods->%* ) {
            $q1->do( [$method] );
        }
    }

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
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 172, 183, 192, 200,  | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |      | 208                  |                                                                                                                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
