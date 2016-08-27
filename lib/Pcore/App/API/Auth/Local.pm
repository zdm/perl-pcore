package Pcore::App::API::Auth::Local;

use Pcore -class;
use Pcore::App::API::RPC::Hash;
use Pcore::Util::Hash::RandKey;
use Pcore::Util::Status;

with qw[Pcore::App::API::Auth];

has dbh => ( is => 'ro', isa => ConsumerOf ['Pcore::DBH'], required => 1 );

has _hash_rpc => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::PM::RPC'], init_arg => undef );
has _hash_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Hash::RandKey'], default => sub { Pcore::Util::Hash::RandKey->new }, init_arg => undef );

sub BUILD ( $self, $args ) {
    $self->_ddl_upgrade;

    return;
}

sub _ddl_upgrade ($self) {

    # create db
    my $ddl = $self->dbh->ddl;

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
                `id` BLOB PRIMARY KEY NOT NULL,
                `app_id` BLOB NOT NULL,
                `version` BLOB NOT NULL,
                `class` BLOB NOT NULL,
                `name` BLOB NOT NULL,
                `desc` TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS `api_role_has_method` (
                `api_role_id` INTEGER NOT NULL REFERENCES `api_role` (`id`) ON DELETE CASCADE,
                `api_method_id` BLOB NOT NULL REFERENCES `api_method` (`id`) ON DELETE CASCADE
            );
SQL
    );

    $ddl->upgrade;

    return;
}

sub _build__hash_rpc($self) {
    return P->pm->run_rpc(
        'Pcore::App::API::RPC::Hash',
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

sub auth_method ( $self, $mid, $rid, $cb ) {
    return 1;
}

# TODO - create user with uid = 1 if not exitst, return new password
sub set_root_password ( $self, $password = undef ) {
    my $blocking_cv = AE::cv;

    $password //= P->random->bytes_hex(32);

    state $q1 = $self->dbh->query('SELECT id FROM api_user WHERE id = 1');

    state $q2 = $self->dbh->query(q[INSERT INTO api_user (id, username, password, enabled) VALUES (1, 'root', ?, 1)]);

    state $q3 = $self->dbh->query('UPDATE api_user SET password = ? WHERE id = 1');

    $q2->do( [$password] ) if !$q1->selectall_arrayref;

    $self->_hash_rpc->rpc_call(
        'create_scrypt',
        $password,
        sub ( $status, $password_hash ) {
            $q3->do( [$password_hash] );

            $blocking_cv->send($password);

            return;
        }
    );

    return $blocking_cv->recv;
}

sub create_user ( $self, $username, $password, $cb ) {
    state $q1 = $self->dbh->query(q[INSERT OR IGNORE INTO api_user (username, password, enabled) VALUES (?, '', 0)]);

    state $q2 = $self->dbh->query('UPDATE api_user SET password = ?, enabled = 1 WHERE id = ?');

    if ( $q1->do( [$username] ) ) {
        $password //= P->random->bytes_hex(32);

        my $uid = $self->dbh->last_insert_id;

        $self->_hash_rpc->rpc_call(
            'create_scrypt',
            $password,
            sub ( $status, $password_hash ) {
                $q2->do( [ $password_hash, $uid ] );

                $cb->( Pcore::Util::Status->new( { status => 200 } ), $uid, $password );

                return;
            }
        );
    }
    else {
        $cb->( Pcore::Util::Status->new( { status => [ '201', 'User already exists' ] } ) );
    }

    return;
}

sub create_role ( $self, $rolename, $cb ) {
    return;
}

sub set_user_password ( $self, $uid, $password, $cb ) {
    return;
}

sub set_enable_user ( $self, $uid, $enabled, $cb ) {
    return;
}

# TODO update api methods in database, or upload api map to cluster
sub upload_api_map ( $self, $map ) {
    my $local_methods = $map->method;

    my $remote_methods = $self->dbh->selectall_hashref( 'SELECT * FROM api_method WHERE app_id = ?', [ $self->api->app_id ], key_cols => 'id' );

    my ( $add_methods, $remove_methods, $update_methods );

    for my $method_id ( keys $local_methods->%* ) {
        if ( !exists $remote_methods->{$method_id} ) {
            $add_methods->{$method_id} = undef;
        }
        else {
            if ( $remote_methods->{$method_id}->{desc} ne $local_methods->{$method_id}->{desc} ) {
                $update_methods->{$method_id} = undef;
            }
        }
    }

    for my $method_id ( keys $remote_methods->%* ) {
        if ( !exists $local_methods->{$method_id} ) {
            $remove_methods->{$method_id} = undef;
        }
    }

    if ($add_methods) {
        my $q1 = $self->dbh->query('INSERT INTO api_method (id, app_id, version, class, name, desc) VALUES (?, ?, ?, ?, ?, ?)');

        for my $method_id ( keys $add_methods->%* ) {
            $q1->do( [ $method_id, $self->api->app_id, $local_methods->{$method_id}->{version}, $local_methods->{$method_id}->{class_path}, $local_methods->{$method_id}->{method_name}, $local_methods->{$method_id}->{desc} ] );
        }
    }

    if ($update_methods) {
        my $q1 = $self->dbh->query('UPDATE api_method SET desc = ? WHERE id = ?');

        for my $method_id ( keys $update_methods->%* ) {
            $q1->do( [ $local_methods->{$method_id}->{desc}, $method_id ] );
        }
    }

    if ($remove_methods) {
        my $q1 = $self->dbh->query('DELETE FROM api_method WHERE id = ?');

        for my $method_id ( keys $remove_methods->%* ) {
            $q1->do( [$method_id] );
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
            $str, $hash,
            sub ( $status, $match ) {
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
## |    3 | 228, 239, 248, 256,  | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |      | 264                  |                                                                                                                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
