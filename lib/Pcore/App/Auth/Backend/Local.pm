package Pcore::App::Auth::Backend::Local;

use Pcore -const, -role, -res, -sql;
use Pcore::App::Auth qw[:ALL];
use Pcore::Util::Data qw[to_b64_url];
use Pcore::Util::Digest qw[sha3_512];
use Pcore::Util::Text qw[encode_utf8];
use Pcore::Util::Scalar qw[looks_like_number looks_like_uuid];
use Pcore::Util::UUID qw[uuid_v4];

with qw[Pcore::App::Auth];

has dbh         => ( init_arg => undef );    # InstanceOf ['Pcore::Handle::DBI']
has _hash_cache => ( init_arg => undef );    # InstanceOf ['Pcore::Util::Hash::LRU']
has _hash_cache_size => 10_000;              # PositiveInt;

sub init ( $self ) {
    $self->{_hash_cache} = P->hash->limited( $self->{_hash_cache_size} );

    # create DBH
    $self->{dbh} = P->handle( $self->{app}->{cfg}->{auth}->{backend} );

    # update schema
    $self->_db_add_schema_patch( $self->{dbh} );

    print 'Upgrading API DB schema ... ';

    say my $res = $self->{dbh}->upgrade_schema;

    return $res unless $res;

    my $permissions = $self->{app}->get_permissions;

    # add permissions
    ( $res = $self->_db_add_permissions( $self->{dbh}, $permissions ) ) || return $res;

    # run hash RPC
    print 'Starting API RPC node ... ';

    say $self->{app}->{node}->run_node(
        {   type      => 'Pcore::App::Auth::Node',
            workers   => $self->{app}->{cfg}->{auth}->{node}->{workers},
            buildargs => $self->{app}->{cfg}->{auth}->{node}->{argon},
        },
    );

    $self->{app}->{node}->wait_node('Pcore::App::Auth::Node');

    print 'Creating root user ... ';

    my $root_password = P->random->bytes_hex(32);

    $res = $self->create_user( 'root', $root_password, 1, undef );

    say $res . ( $res ? ", password: $root_password" : $EMPTY );

    return res 200;
}

# AUTHENTICATE
sub do_authenticate_private ( $self, $private_token ) {
    if ( $private_token->[0] == $TOKEN_TYPE_PASSWORD ) {
        return $self->_auth_user_password($private_token);
    }
    elsif ( $private_token->[0] == $TOKEN_TYPE_TOKEN ) {
        return $self->_auth_user_token($private_token);
    }
    elsif ( $private_token->[0] == $TOKEN_TYPE_SESSION ) {
        return $self->_auth_user_token($private_token);
    }
    else {
        return res [ 400, 'Invalid token type' ];
    }
}

# TOKENS / HASH GENERATORS
sub validate_name ( $self, $name ) {

    # name looks like UUID string
    return if looks_like_uuid $name;

    # name looks like number
    return if looks_like_number $name;

    return if $name =~ /[^[:alnum:]_@.-]/smi;

    return 1;
}

sub _verify_token_hash ( $self, $private_token_hash, $hash ) {
    my $cache_id = "$hash/$private_token_hash";

    if ( exists $self->{_hash_cache}->{$cache_id} ) {
        return $self->{_hash_cache}->{$cache_id};
    }
    else {
        my $res = $self->{app}->{node}->rpc_call( 'Pcore::App::Auth::Node', 'verify_hash', $private_token_hash, $hash );

        return $self->{_hash_cache}->{$cache_id} = $res->{data} ? res 200 : res [ 400, 'Invalid token' ];
    }
}

sub _generate_user_password_hash ( $self, $user_name_utf8, $user_password_utf8 ) {
    my $user_name_bin = encode_utf8 $user_name_utf8;

    my $user_password_bin = encode_utf8 $user_password_utf8;

    my $private_token_hash = sha3_512 $user_password_bin . $user_name_bin;

    my $res = $self->{app}->{node}->rpc_call( 'Pcore::App::Auth::Node', 'create_hash', $private_token_hash );

    return $res if !$res;

    return res 200, { hash => $res->{data} };
}

sub _generate_token ( $self, $token_type ) {
    my $token_id = uuid_v4;

    my $public_token = to_b64_url pack( 'C', $token_type ) . $token_id->bin . P->random->bytes(32);

    my $private_token_hash = sha3_512 $public_token;

    my $res = $self->{app}->{node}->rpc_call( 'Pcore::App::Auth::Node', 'create_hash', $private_token_hash );

    return $res if !$res;

    return res 200, { id => $token_id->str, token => $public_token, hash => $res->{data} };
}

sub _return_auth ( $self, $private_token, $user_id, $user_name ) {
    my $auth = {
        private_token => $private_token,

        is_root   => $user_name eq 'root' ? 1 : 0,
        user_id   => $user_id,
        user_name => $user_name,

        permissions => {},
    };

    # is a root user
    return res 200, $auth if $auth->{is_root};

    if ( $private_token->[0] == $TOKEN_TYPE_TOKEN ) {
        my $res = $self->_db_get_user_token_permissions( $self->{dbh}, $private_token->[1] );

        return $res if !$res;

        $auth->{permissions} = { map { $_->{permission_name} => 1 } $res->{data}->@* };

        return res 200, $auth;
    }
    else {
        my $res = $self->_db_get_user_permissions( $self->{dbh}, $user_id );

        return $res if !$res;

        $auth->{permissions} = { map { $_->{permission_name} => 1 } $res->{data}->@* };

        return res 200, $auth;
    }
}

# USER
sub _auth_user_password ( $self, $private_token ) {

    # get user
    state $q1 = $self->{dbh}->prepare(q[SELECT "id", "hash", "enabled" FROM "auth_user" WHERE "name" = ?]);

    my $user = $self->{dbh}->selectrow( $q1, [ $private_token->[1] ] );

    # user not found
    return res [ 404, 'User not found' ] if !$user->{data};

    # user is disabled
    return res [ 404, 'User is disabled' ] if !$user->{data}->{enabled};

    # verify token
    my $status = $self->_verify_token_hash( $private_token->[2], $user->{data}->{hash} );

    # token is invalid
    return $status if !$status;

    # token is valid
    return $self->_return_auth( $private_token, $user->{data}->{id}, $private_token->[1] );
}

sub create_user ( $self, $user_name, $password, $enabled, $permissions ) {

    # validate user name
    return res [ 400, 'User name is not valid' ] if !$self->validate_name($user_name);

    # lowercase user name
    $user_name = lc $user_name;

    state $on_finish = sub ( $dbh, $res ) {
        if ( !$res ) {
            my $res1 = $dbh->rollback;

            return $res;
        }
        else {
            my $res1 = $dbh->commit;

            # error committing transaction
            return $res1 if !$res1;

            return $res;
        }

        return;
    };

    # get dbh
    my ( $res, $dbh ) = $self->{dbh}->get_dbh;

    # unable to get dbh
    return $res if !$res;

    # start transaction
    $res = $dbh->begin_work;

    # failed to start transaction
    return $res if !$res;

    # check, that user is not exists
    my $user = $self->_db_get_user( $dbh, $user_name );

    # user already exists
    return $on_finish->( $dbh, res [ 400, 'User name already exists' ] ) if $user;

    # generate user password hash
    $res = $self->_generate_user_password_hash( $user_name, $password );

    # error generating hash
    return $on_finish->( $dbh, res 500 ) if !$res;

    # insert user
    $user = $self->_db_create_user( $dbh, $user_name, $res->{data}->{hash}, $enabled );

    # failed to insert user
    return $on_finish->( $dbh, res 500 ) if !$user;

    # set user permissions
    $res = $self->_set_user_permissions( $dbh, $user->{data}->{id}, $permissions );

    return $on_finish->( $dbh, $res ) if !$res;

    return $on_finish->( $dbh, $user );
}

sub get_users ( $self ) {
    return $self->_db_get_users( $self->{dbh} );
}

sub get_user ( $self, $user_id ) {
    return $self->_db_get_user( $self->{dbh}, $user_id );
}

sub set_user_permissions ( $self, $user_id, $permissions ) {

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    return $user if !$user;

    # get dbh
    my ( $res, $dbh ) = $self->{dbh}->get_dbh;

    # unable to get dbh
    return $res if !$res;

    # start transaction
    $res = $dbh->begin_work;

    # failed to start transaction
    return $res if !$res;

    $res = $self->_set_user_permissions( $dbh, $user->{data}->{id}, $permissions );

    # sql error
    if ( !$res ) {
        my $res1 = $dbh->rollback;

        return $res;
    }
    else {
        my $res1 = $dbh->commit;

        # commit error
        return $res1 if !$res1;

        # fire event if user permissions was changed
        P->fire_event( 'app.api.auth', { type => $INVALIDATE_USER, id => $user->{data}->{id} } ) if $res == 200;

        return $res;
    }
}

sub _set_user_permissions ( $self, $dbh, $user_id, $permissions ) {
    return res 204 if !$permissions || !$permissions->@*;    # not modified

    my $all_permissions = $self->_db_get_permissions($dbh);

    # error retrieving permissions
    return $all_permissions if !$all_permissions;

    my $idx;

    for ( values $all_permissions->{data}->%* ) {
        $idx->{id}->{ $_->{id} } = $_->{name};

        $idx->{name}->{ $_->{name} } = $_->{id};
    }

    my $permissions_ids;

    for my $permission ( $permissions->@* ) {
        if ( looks_like_uuid $permission) {

            # permission id is invalid
            return res [ 400, qq[permission id "$permission" is invlalid] ] if !exists $idx->{id}->{$permission};

            push $permissions_ids->@*, $permission;
        }
        else {

            # permission name is invalid
            return res [ 400, qq[permission name "$permission" is invlalid] ] if !exists $idx->{name}->{$permission};

            push $permissions_ids->@*, $idx->{name}->{$permission};
        }
    }

    return $self->_db_set_user_permissions( $dbh, $user_id, $permissions_ids );
}

sub set_user_password ( $self, $user_id, $password ) {

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    return $user if !$user;

    my $password_hash = $self->_generate_user_password_hash( $user->{data}->{name}, $password );

    # password hash genereation error
    return $password_hash if !$password_hash;

    # password hash generated
    state $q1 = $self->{dbh}->prepare(q[UPDATE "auth_user" SET "hash" = ? WHERE "id" = ?]);

    my $res = $self->{dbh}->do( $q1, [ SQL_BYTEA $password_hash->{data}->{hash}, SQL_UUID $user->{data}->{id} ] );

    return res 500 if !$res->{rows};

    # fire AUTH event if user password was changed
    P->fire_event( 'app.api.auth', { type => $INVALIDATE_TOKEN, id => $user->{data}->{name} } );

    return res 200;
}

sub set_user_enabled ( $self, $user_id, $enabled ) {

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    return $user if !$user;

    $enabled = 0+ !!$enabled;

    if ( $enabled ^ $user->{data}->{enabled} ) {
        state $q1 = $self->{dbh}->prepare(q[UPDATE "auth_user" SET "enabled" = ? WHERE "id" = ?]);

        my $res = $self->{dbh}->do( $q1, [ SQL_BOOL $enabled, SQL_UUID $user->{data}->{id} ] );

        return $res if !$res;

        return res 500 if !$res->{rows};

        # fire AUTH event if user was disabled
        P->fire_event( 'app.api.auth', { type => $INVALIDATE_USER, id => $user->{data}->{id} } ) if !$enabled;

        return res 200, { enabled => $enabled };
    }
    else {

        # not modified
        return res 204, { enabled => $enabled };
    }
}

# USER TOKEN
sub _auth_user_token ( $self, $private_token ) {

    # get user token
    state $q1 = $self->{dbh}->prepare(
        <<'SQL'
            SELECT
                "auth_user"."id" AS "user_id",
                "auth_user"."name" AS "user_name",
                "auth_user"."enabled" AS "user_enabled",
                "auth_user_token"."hash" AS "user_token_hash"
            FROM
                "auth_user",
                "auth_user_token"
            WHERE
                "auth_user"."id" = "auth_user_token"."user_id"
                AND "auth_user_token"."id" = ?
SQL
    );

    my $user_token = $self->{dbh}->selectrow( $q1, [ SQL_UUID $private_token->[1] ] );

    # user is disabled
    return res 404 if !$user_token->{data}->{user_enabled};

    # verify token
    my $status = $self->_verify_token_hash( $private_token->[2], $user_token->{data}->{user_token_hash} );

    # token is not valid
    return $status if !$status;

    # token is valid
    return $self->_return_auth( $private_token, $user_token->{data}->{user_id}, $user_token->{data}->{user_name} );
}

sub create_user_token ( $self, $user_id, $desc, $permissions ) {

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    return $user if !$user;

    # generate user token
    my $token = $self->_generate_token($TOKEN_TYPE_TOKEN);

    # token generation error
    return $token if !$token;

    # get user permissions
    my $user_permissions = $self->_db_get_user_permissions( $self->{dbh}, $user->{data}->{id} );

    # error
    return $user_permissions if !$user_permissions;

    # find user permissions id's
    if ( defined $permissions ) {

        # create index by permission name
        my $idx = { map { $_ => 1 } $permissions->@* };

        $user_permissions = [ grep { exists $idx->{ $_->{permission_name} } } $user_permissions->{data}->@* ];

        # some permissions are invalid or not allowed
        return res 500 if $permissions->@* != $user_permissions->{data}->@*;
    }

    # get dbh
    my ( $res, $dbh ) = $self->{dbh}->get_dbh;

    # unable to get dbh
    return $res if !$res;

    # start transaction
    $res = $dbh->begin_work;

    # failed to start transaction
    return $res if !$res;

    my $on_finish = sub ($res) {
        if ( !$res ) {
            my $res1 = $dbh->rollback;

            return res 500;
        }
        else {
            my $res1 = $dbh->commit;

            # commit error
            return $res1 if !$res1;

            return res 200,
              { id    => $token->{data}->{id},
                type  => $TOKEN_TYPE_TOKEN,
                token => $token->{data}->{token},
              };
        }
    };

    # insert token
    state $q1 = $dbh->prepare('INSERT INTO "auth_user_token" ("id", "type", "user_id", "hash", "desc" ) VALUES (?, ?, ?, ?, ?)');

    $res = $dbh->do( $q1, [ SQL_UUID $token->{data}->{id}, $TOKEN_TYPE_TOKEN, SQL_UUID $user->{data}->{id}, SQL_BYTEA $token->{data}->{hash}, $desc ] );

    return $on_finish->($res) if !$res;

    # no permissions to insert, eg: root user
    return $on_finish->($res) if !$user_permissions->@*;

    # insert user token permissions
    $res = $dbh->do( [ q[INSERT INTO "auth_user_token_permission"], VALUES [ map { { user_token_id => SQL_UUID $token->{data}->{id}, user_permission_id => SQL_UUID $_->{id} } } $user_permissions->{data}->@* ] ] );

    return $on_finish->($res);
}

sub remove_user_token ( $self, $user_token_id ) {
    state $q1 = $self->{dbh}->prepare('DELETE FROM "auth_user_token" WHERE "id" = ? AND "type" = ?');

    my $res = $self->{dbh}->do( $q1, [ SQL_UUID $user_token_id, $TOKEN_TYPE_TOKEN ] );

    return $res if !$res;

    # not found
    return res 204 if !$res->{rows};

    P->fire_event( 'app.api.auth', { type => $INVALIDATE_TOKEN, id => $user_token_id } );

    return res 200;
}

# USER SESSION
sub create_user_session ( $self, $user_id ) {

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    return $user if !$user;

    # generate session token
    my $token = $self->_generate_token($TOKEN_TYPE_SESSION);

    # token generation error
    return $token if !$token;

    # token geneerated
    state $q1 = $self->{dbh}->prepare('INSERT INTO "auth_user_token" ("id", "type", "user_id", "hash") VALUES (?, ?, ?, ?)');

    my $res = $self->{dbh}->do( $q1, [ SQL_UUID $token->{data}->{id}, $TOKEN_TYPE_SESSION, SQL_UUID $user->{data}->{id}, SQL_BYTEA $token->{data}->{hash} ] );

    return res 500 if !$res->{rows};

    return res 200,
      { id    => $token->{data}->{id},
        type  => $TOKEN_TYPE_SESSION,
        token => $token->{data}->{token},
      };
}

sub remove_user_session ( $self, $user_sid ) {
    state $q1 = $self->{dbh}->prepare('DELETE FROM "auth_user_token" WHERE "id" = ? AND "type" = ?');

    my $res = $self->{dbh}->do( $q1, [ SQL_UUID $user_sid, $TOKEN_TYPE_SESSION ] );

    return $res if !$res;

    # not found
    return res 204 if !$res->{rows};

    P->fire_event( 'app.api.auth', { type => $INVALIDATE_TOKEN, id => $user_sid } );

    return res 200;
}

# DB METHODS
sub _db_get_users ( $self, $dbh ) {
    state $q1 = $dbh->prepare(q[SELECT "id", "name", "enabled", "created" FROM "auth_user"]);

    return $dbh->selectall($q1);
}

sub _db_get_user ( $self, $dbh, $user_id ) {
    my $user;

    # find user by id
    if ( looks_like_uuid $user_id) {
        state $q1 = $dbh->prepare(q[SELECT "id", "name", "enabled", "created" FROM "auth_user" WHERE "id" = ?]);

        $user = $dbh->selectrow( $q1, [ SQL_UUID $user_id ] );
    }

    # find user by name
    else {
        state $q1 = $dbh->prepare(q[SELECT "id", "name", "enabled", "created" FROM "auth_user" WHERE "name" = ?]);

        $user = $dbh->selectrow( $q1, [$user_id] );
    }

    # query error
    return $user if !$user;

    # user not found
    return res [ 404, 'User not found' ] if !$user->{data};

    return $user;
}

sub _db_get_permissions ( $self, $dbh ) {
    state $q1 = $dbh->prepare(q[SELECT * FROM "auth_permission"]);

    return $dbh->selectall( $q1, key_field => 'id' );
}

sub _db_get_user_permissions ( $self, $dbh, $user_id ) {
    state $q1 = $dbh->prepare(
        <<'SQL',
            SELECT
                "auth_user_permission"."id" AS "id",
                "auth_permission"."id" AS "permission_id",
                "auth_permission"."name" AS "permission_name"
            FROM
                "auth_user_permission",
                "auth_permission"
            WHERE
                "auth_user_permission"."permission_id" = "auth_permission"."id"
                AND "auth_user_permission"."user_id" = ?
SQL
    );

    return $dbh->selectall( $q1, [ SQL_UUID $user_id ] );
}

sub _db_get_user_token_permissions ( $self, $dbh, $user_token_id ) {
    state $q1 = $dbh->prepare(
        <<'SQL',
            SELECT
                "auth_user_token_permission"."id" AS "id",
                "auth_permission"."id" AS "permission_id",
                "auth_permission"."name" AS "permission_name"
            FROM
                "auth_user_token_permission",
                "auth_user_permission",
                "auth_permission"
            WHERE
                "auth_user_token_permission"."user_permission_id" = "auth_user_permission"."id"
                AND "auth_user_permission"."permission_id" = "auth_permission"."id"
                AND "auth_user_token_permission"."user_token_id" = ?
SQL
    );

    return $dbh->selectall( $q1, [ SQL_UUID $user_token_id ] );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 103, 131, 189        | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::Auth::Backend::Local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
