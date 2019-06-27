package Pcore::App::Auth::Backend::Local;
use Pcore -const, -role, -res, -sql;
use Pcore::App::Auth qw[:ALL];
use Pcore::Util::Data qw[to_b64_url];
use Pcore::Util::Digest qw[sha3_512];
use Pcore::Util::Text qw[encode_utf8];
use Pcore::Util::Scalar qw[looks_like_number looks_like_uuid];
use Pcore::Util::UUID qw[$UUID_ZERO uuid_v4 uuid_v4_str];

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

    # sync app permissions
    ( $res = $self->_sync_app_permissions($permissions) ) || return $res;

    # app permissions was changed, invalidate cache
    P->fire_event( 'app.auth.cache', { type => $INVALIDATE_ALL } ) if $res == 200;

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

    $res = $self->create_user( $ROOT_USER_NAME, $root_password, 1, undef );

    say $res . ( $res ? ", password: $root_password" : $EMPTY );

    return res 200;
}

# AUTHENTICATE
sub do_authenticate_private ( $self, $private_token ) {
    if ( $private_token->[$PRIVATE_TOKEN_TYPE] == $TOKEN_TYPE_PASSWORD ) {
        return $self->_auth_password($private_token);
    }
    else {
        return $self->_auth_token($private_token);
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

sub _verify_password_hash ( $self, $private_token_hash, $hash ) {
    my $cache_id = "$hash/$private_token_hash";

    if ( exists $self->{_hash_cache}->{$cache_id} ) {
        return $self->{_hash_cache}->{$cache_id};
    }
    else {
        my $res = $self->{app}->{node}->rpc_call( 'Pcore::App::Auth::Node', 'verify_hash', $private_token_hash, $hash );

        return $self->{_hash_cache}->{$cache_id} = $res->{data} ? res 200 : res [ 400, 'Invalid token' ];
    }
}

sub _generate_password_hash ( $self, $user_name_utf8, $user_password_utf8 ) {
    my $user_name_bin = encode_utf8 $user_name_utf8;

    my $user_password_bin = encode_utf8 $user_password_utf8;

    my $private_token_hash = sha3_512 $user_password_bin . $user_name_bin;

    my $res = $self->{app}->{node}->rpc_call( 'Pcore::App::Auth::Node', 'create_hash', $private_token_hash );

    return $res if !$res;

    return res 200, { hash => $res->{data} };
}

sub _generate_token ( $self ) {
    my $token_id = uuid_v4;

    my $rand = P->random->bytes(32);

    my $token_bin = $token_id->bin . $rand;

    my $private_token_hash = sha3_512 $rand;

    return res 200,
      { id    => $token_id->str,
        token => to_b64_url $token_bin,
        hash  => sha3_512 $private_token_hash . $token_id->str,
      };
}

sub _return_auth ( $self, $private_token, $user_id, $user_name ) {
    my $auth = {
        private_token => $private_token,

        is_root   => $self->user_is_root($user_name),
        user_id   => $user_id,
        user_name => $user_name,

        permissions => {},
    };

    my $permissions;

    # get token permissions
    if ( $private_token->[$PRIVATE_TOKEN_TYPE] == $TOKEN_TYPE_TOKEN ) {
        $permissions = $self->get_token_permissions( $private_token->[$PRIVATE_TOKEN_ID] );
    }

    # get user permissions, session tokens inherit user permissions
    else {
        $permissions = $self->get_user_permissions($user_id);
    }

    # get permissions error
    return $permissions if !$permissions;

    $auth->{permissions} = $permissions->{data};

    return res 200, $auth;
}

# APP
sub _sync_app_permissions ( $self, $permissions ) {
    my $dbh = $self->{dbh};

    my $modified = 0;

    # insert permissions
    my $res = $dbh->do( [ q[INSERT INTO "auth_app_permission"], VALUES [ map { { name => $_ } } $permissions->@* ], 'ON CONFLICT DO NOTHING' ] );

    return $res if !$res;

    $modified += $res->{rows};

    # enable permissions
    $res = $dbh->do( [ q[UPDATE "auth_app_permission" SET "enabled" = TRUE WHERE "enabled" = FALSE AND "name"], IN $permissions ] );

    return $res if !$res;

    $modified += $res->{rows};

    # disable removed permissions
    $res = $dbh->do( [ q[UPDATE "auth_app_permission" SET "enabled" = FALSE WHERE "enabled" = TRUE AND "name" NOT], IN $permissions ] );

    return $res if !$res;

    $modified += $res->{rows};

    return res( $modified ? 200 : 204 );
}

sub get_app_permissions ( $self ) {
    state $q1 = $self->{dbh}->prepare(
        <<'SQL',
        SELECT
            "name",
            "enabled"
        FROM
            "auth_app_permission"
        WHERE
            "auth_app_permission"."enabled" = TRUE
SQL
    );

    my $res = $self->{dbh}->selectall($q1);

    # DBH error
    return $res if !$res;

    return res 200, { map { $_->{name} => $_->{enabled} } $res->{data}->@* };
}

# USER
sub _auth_password ( $self, $private_token ) {

    # get user
    state $q1 = $self->{dbh}->prepare(q[SELECT "id", "hash", "enabled" FROM "auth_user" WHERE "name" = ?]);

    my $user = $self->{dbh}->selectrow( $q1, [ $private_token->[$PRIVATE_TOKEN_ID] ] );

    # user not found
    return res [ 404, 'User not found' ] if !$user->{data};

    # user is disabled
    return res [ 404, 'User is disabled' ] if !$user->{data}->{enabled};

    # verify token
    my $status = $self->_verify_password_hash( $private_token->[$PRIVATE_TOKEN_HASH], $user->{data}->{hash} );

    # token is invalid
    return $status if !$status;

    # token is valid
    return $self->_return_auth( $private_token, $user->{data}->{id}, $private_token->[$PRIVATE_TOKEN_ID] );
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

    # generate user id
    my $user_id = $self->user_is_root($user_name) ? $ROOT_USER_ID : uuid_v4_str;

    state $q1 = $dbh->prepare(q[INSERT INTO "auth_user" ("id", "name", "hash", "enabled") VALUES (?, ?, '', FALSE) ON CONFLICT DO NOTHING]);

    # insert user
    $res = $dbh->do( $q1, [ SQL_UUID $user_id, $user_name ] );

    # DBH error
    return $on_finish->( $dbh, $res ) if !$res;

    # username already exists
    return $on_finish->( $dbh, res [ 400, 'Username is already exists' ] ) if !$res->{rows};

    # generate user password hash
    $res = $self->_generate_password_hash( $user_name, $password );

    # error generating hash
    return $on_finish->( $dbh, $res ) if !$res;

    # update user
    state $q2 = $dbh->prepare(q[UPDATE "auth_user" SET "enabled" = ?, "hash" = ? WHERE "id" = ?]);

    $res = $dbh->do( $q2, [ SQL_BOOL $enabled, SQL_BYTEA $res->{data}->{hash}, SQL_UUID $user_id] );

    # DBH error
    return $on_finish->( $dbh, $res ) if !$res;

    # set user permissions
    $res = $self->_db_set_user_permissions( $dbh, $user_id, $permissions );

    return $on_finish->( $dbh, $res ) if !$res;

    return $on_finish->(
        $dbh,
        res 200,
        {   id      => $user_id,
            name    => $user_name,
            enabled => $enabled,
        }
    );
}

sub get_user ( $self, $user_id ) {
    return $self->_db_get_user( $self->{dbh}, $user_id );
}

sub set_user_password ( $self, $user_id, $password ) {

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    return $user if !$user;

    my $password_hash = $self->_generate_password_hash( $user->{data}->{name}, $password );

    # password hash genereation error
    return $password_hash if !$password_hash;

    # password hash generated
    state $q1 = $self->{dbh}->prepare(q[UPDATE "auth_user" SET "hash" = ? WHERE "id" = ?]);

    my $res = $self->{dbh}->do( $q1, [ SQL_BYTEA $password_hash->{data}->{hash}, SQL_UUID $user->{data}->{id} ] );

    return res 500 if !$res->{rows};

    # fire AUTH event if user password was changed
    P->fire_event( 'app.auth.cache', { type => $INVALIDATE_TOKEN, id => $user->{data}->{name} } );

    return res 200;
}

sub set_user_enabled ( $self, $user_id, $enabled ) {
    my $dbh = $self->{dbh};

    # root can't be disabled
    state $q1 = $dbh->prepare(q[UPDATE "auth_user" SET "enabled" = ? WHERE ("id" = ? OR "name" = ?) AND "name" != ? AND "enabled" = ?]);

    my $res = $dbh->do(
        $q1,
        [    #
            SQL_BOOL $enabled,
            SQL_UUID( looks_like_uuid $user_id ? $user_id : $UUID_ZERO ),
            $user_id,
            $ROOT_USER_NAME,
            SQL_BOOL !$enabled,
        ]
    );

    # DBH error
    return $res if !$res;

    # modified
    if ( $res->{rows} ) {
        P->fire_event( 'app.auth.cache', { type => $INVALIDATE_USER, id => $user_id } );

        return res 200, { enabled => 0+ !!$enabled };
    }

    # not modified
    else {
        return res 204, { enabled => 0+ !!$enabled };
    }
}

sub get_user_permissions ( $self, $user_id ) {
    state $q1 = $self->{dbh}->prepare(
        <<'SQL',
        SELECT
            "auth_app_permission"."name",
            CASE
                WHEN "auth_user"."name" = ? THEN TRUE
                ELSE COALESCE("auth_user_permission"."enabled", FALSE)
            END  AS "enabled"
        FROM
            "auth_app_permission"
            LEFT JOIN "auth_user" ON (
                "auth_user"."id" = ?
                OR "auth_user"."name" = ?
            )
            LEFT JOIN "auth_user_permission" ON (
                "auth_user_permission"."permission_id" = "auth_app_permission"."id"
                AND "auth_user_permission"."user_id" = "auth_user"."id"
            )
        WHERE
            "auth_app_permission"."enabled" = TRUE
SQL
    );

    my $res = $self->{dbh}->selectall( $q1, [ $ROOT_USER_NAME, SQL_UUID( looks_like_uuid $user_id ? $user_id : $UUID_ZERO ), $user_id ] );

    # DBH error
    return $res if !$res;

    return res 200, { map { $_->{name} => $_->{enabled} } $res->{data}->@* };
}

sub set_user_permissions ( $self, $user_id, $permissions ) {

    # get dbh
    my ( $res, $dbh ) = $self->{dbh}->get_dbh;

    # unable to get dbh
    return $res if !$res;

    # resolve user
    my $user = $self->_db_get_user( $dbh, $user_id );

    # user wasn't found
    return $user if !$user;

    return res [ 400, q[Can't modify "root" user permissions] ] if $self->user_is_root( $user->{data}->{name} );

    # start transaction
    $res = $dbh->begin_work;

    # failed to start transaction
    return $res if !$res;

    $res = $self->_db_set_user_permissions( $dbh, $user->{data}->{id}, $permissions );

    # set permissions error
    if ( !$res ) {
        my $rollback = $dbh->rollback;

        return $res;
    }

    # commit
    my $commit = $dbh->commit;

    # commit error
    return $commit if !$commit;

    # permissions was modified
    P->fire_event( 'app.auth.cache', { type => $INVALIDATE_USER, id => $user->{data}->{id} } ) if $res == 200;

    return $res;
}

# TOKEN
sub _auth_token ( $self, $private_token ) {

    # get user token
    state $q1 = $self->{dbh}->prepare(
        <<'SQL'
            SELECT
                "auth_user"."id" AS "user_id",
                "auth_user"."name" AS "user_name",
                "auth_user"."enabled" AS "user_enabled",
                "auth_token"."enabled" AS "token_enabled",
                "auth_token"."type" AS "token_type",
                "auth_token"."hash" AS "token_hash"
            FROM
                "auth_user",
                "auth_token"
            WHERE
                "auth_user"."id" = "auth_token"."user_id"
                AND "auth_token"."id" = ?
SQL
    );

    my $token = $self->{dbh}->selectrow( $q1, [ SQL_UUID $private_token->[$PRIVATE_TOKEN_ID] ] );

    # DBH error
    return res 500 if !$token;

    $token = $token->{data};

    # user or token is disabled
    return res 404 if !$token || !$token->{user_enabled} || !$token->{token_enabled};

    # verify token, token is not valid
    return res [ 400, 'Invalid token' ] if sha3_512( $private_token->[$PRIVATE_TOKEN_HASH] . $private_token->[$PRIVATE_TOKEN_ID] ) ne $token->{token_hash};

    # store token type in private token
    $private_token->[$PRIVATE_TOKEN_TYPE] = $token->{token_type};

    # token is valid
    return $self->_return_auth( $private_token, $token->{user_id}, $token->{user_name} );
}

sub get_user_tokens ( $self, $user_id ) {
    state $q1 = $self->{dbh}->prepare(q[SELECT "id", "name", "enabled", "created" FROM "auth_token" WHERE "type" = ? AND "user_id" = ?]);

    return $self->{dbh}->selectall( $q1, [ $TOKEN_TYPE_TOKEN, SQL_UUID $user_id] );
}

sub get_token ( $self, $token_id ) {
    state $q1 = $self->{dbh}->prepare(q[SELECT "id", "name", "enabled", "created", "user_id" FROM "auth_token" WHERE "type" = ? AND "id" = ?]);

    return $self->{dbh}->selectrow( $q1, [ $TOKEN_TYPE_TOKEN, SQL_UUID $token_id] );
}

# TODO
sub create_token ( $self, $user_id, $name, $permissions ) {

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    return $user if !$user;

    # generate user token
    my $token = $self->_generate_token;

    # token generation error
    return $token if !$token;

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
    state $q1 = $dbh->prepare('INSERT INTO "auth_token" ("id", "type", "user_id", "hash", "name" ) VALUES (?, ?, ?, ?, ?)');

    $res = $dbh->do( $q1, [ SQL_UUID $token->{data}->{id}, $TOKEN_TYPE_TOKEN, SQL_UUID $user->{data}->{id}, SQL_BYTEA $token->{data}->{hash}, $name ] );

    return $on_finish->($res) if !$res;

    return $on_finish->($res);

    # # get user permissions
    # my $user_permissions = $self->_db_get_user_permissions( $self->{dbh}, $user->{data}->{id} );

    # # error
    # return $user_permissions if !$user_permissions;

    # # find user permissions id's
    # if ( defined $permissions ) {

    #     # create index by permission name
    #     my $idx = { map { $_ => 1 } $permissions->@* };

    #     $user_permissions = [ grep { exists $idx->{ $_->{permission_name} } } $user_permissions->{data}->@* ];

    #     # some permissions are invalid or not allowed
    #     return res 500 if $permissions->@* != $user_permissions->{data}->@*;
    # }

    # # no permissions to insert, eg: root user
    # return $on_finish->($res) if !$user_permissions->@*;

    # # insert user token permissions
    # $res = $dbh->do( [ q[INSERT INTO "auth_token_permission"], VALUES [ map { { token_id => SQL_UUID $token->{data}->{id}, user_permission_id => SQL_UUID $_->{id} } } $user_permissions->{data}->@* ] ] );

    # return $on_finish->($res);
}

sub remove_token ( $self, $token_id ) {
    return $self->_remove_token( $token_id, $TOKEN_TYPE_TOKEN );
}

sub set_token_enabled ( $self, $token_id, $enabled ) {
    my $dbh = $self->{dbh};

    state $q1 = $dbh->prepare(q[UPDATE "auth_token" SET "enabled" = ? WHERE "id" = ? AND "type" = ? AND "enabled" = ?]);

    my $res = $dbh->do( $q1, [ SQL_BOOL $enabled, SQL_UUID $token_id, $TOKEN_TYPE_TOKEN, SQL_BOOL !$enabled ] );

    # DBH error
    return $res if !$res;

    # modified
    if ( $res->{rows} ) {
        P->fire_event( 'app.auth.cache', { type => $INVALIDATE_TOKEN, id => $token_id } );

        return res 200, { enabled => 0+ !!$enabled };
    }

    # not modified
    else {
        return res 204, { enabled => 0+ !!$enabled };
    }
}

# TODO user_permission is always enabled for root
sub get_token_permissions ( $self, $token_id ) {
    state $q1 = $self->{dbh}->prepare(
        <<'SQL',
        SELECT
            "auth_app_permission"."name",
            COALESCE("auth_token_permission"."enabled" AND "auth_user_permission"."enabled", FALSE) AS "enabled"
        FROM
            "auth_app_permission"
            LEFT JOIN "auth_token_permission" ON (
                "auth_token_permission"."permission_id" = "auth_app_permission"."id"
                AND "auth_token_permission"."token_id" = ?
            )
            LEFT JOIN "auth_user_permission" ON (
                "auth_user_permission"."user_id" = "auth_token_permission"."user_id"
                AND "auth_user_permission"."permission_id" = "auth_token_permission"."permission_id"
            )
        WHERE
            "auth_app_permission"."enabled" = TRUE
SQL
    );

    my $res = $self->{dbh}->selectall( $q1, [ SQL_UUID $token_id ] );

    # DBH error
    return $res if !$res;

    return res 200, { map { $_->{name} => $_->{enabled} } $res->{data}->@* };
}

# TODO user_permission is always enabled for root
sub get_token_permissions_for_edit ( $self, $token_id ) {
    state $q1 = $self->{dbh}->prepare(
        <<'SQL',
        SELECT
            "auth_app_permission"."name",
            COALESCE("auth_token_permission"."enabled", FALSE) AS "token_enabled",
            CASE
                WHEN "auth_token_permission"."user_id" = ? THEN TRUE
                ELSE COALESCE("auth_user_permission"."enabled", FALSE)
            END AS "user_enabled",
            CASE
                WHEN "auth_token_permission"."user_id" = ? THEN COALESCE("auth_token_permission"."enabled", FALSE)
                ELSE COALESCE("auth_user_permission"."enabled" AND "auth_token_permission"."enabled", FALSE)
            END AS "enabled",
            CASE
                WHEN "auth_token_permission"."user_id" = ? THEN TRUE
                WHEN "auth_user_permission"."enabled" IS NULL THEN FALSE
                ELSE TRUE
            END  AS "can_edit"
        FROM
            "auth_app_permission"
            LEFT JOIN "auth_token_permission" ON (
                "auth_token_permission"."permission_id" = "auth_app_permission"."id"
                AND "auth_token_permission"."token_id" = ?
            )
            LEFT JOIN "auth_user_permission" ON (
                "auth_user_permission"."user_id" = "auth_token_permission"."user_id"
                AND "auth_user_permission"."permission_id" = "auth_token_permission"."permission_id"
            )
        WHERE
            "auth_app_permission"."enabled" = TRUE
SQL
    );

    my $res = $self->{dbh}->selectall( $q1, [ SQL_UUID $ROOT_USER_ID, SQL_UUID $ROOT_USER_ID, SQL_UUID $ROOT_USER_ID, SQL_UUID $token_id ], key_col => 'name' );

    # DBH error
    return $res if !$res;

    return res 200, $res->{data};
}

# TODO transaction
sub set_token_permissions ( $self, $token_id, $permissions ) {

    # get dbh
    my ( $res, $dbh ) = $self->{dbh}->get_dbh;

    # unable to get dbh
    return $res if !$res;

    $res = $self->_db_set_token_permissions( $dbh, $token_id, $permissions );

    # DBH error
    return $res if !$res;

    # permissions was modified
    P->fire_event( 'app.auth.cache', { type => $INVALIDATE_TOKEN, id => $token_id } ) if $res == 200;

    return $res;
}

# SESSION
sub create_session ( $self, $user_id ) {

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    return $user if !$user;

    # generate session token
    my $token = $self->_generate_token;

    # token generation error
    return $token if !$token;

    # token geneerated
    state $q1 = $self->{dbh}->prepare('INSERT INTO "auth_token" ("id", "type", "user_id", "hash") VALUES (?, ?, ?, ?)');

    my $res = $self->{dbh}->do( $q1, [ SQL_UUID $token->{data}->{id}, $TOKEN_TYPE_SESSION, SQL_UUID $user->{data}->{id}, SQL_BYTEA $token->{data}->{hash} ] );

    # DBH error
    return $res if !$res;

    return res 200,
      { id    => $token->{data}->{id},
        type  => $TOKEN_TYPE_SESSION,
        token => $token->{data}->{token},
      };
}

sub remove_session ( $self, $token_id ) {
    return $self->_remove_token( $token_id, $TOKEN_TYPE_SESSION );
}

# UTIL
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

    # DBH error
    return $user if !$user;

    # user not found
    return res [ 404, 'User not found' ] if !$user->{data};

    return $user;
}

sub _db_set_user_permissions ( $self, $dbh, $user_id, $permissions ) {
    return res 204 if !$permissions || !$permissions->%*;    # not modified

    my $res;
    my $modified = 0;
    my $final_permissions;

    while ( my ( $name, $enabled ) = each $permissions->%* ) {
        state $q1 = $dbh->prepare(q[INSERT INTO "auth_user_permission" ("user_id", "permission_id", "enabled") VALUES (?, (SELECT "id" FROM "auth_app_permission" WHERE "name" = ?), ?) ON CONFLICT DO NOTHING]);

        $res = $dbh->do( $q1, [ SQL_UUID $user_id, $name, SQL_BOOL $enabled] );

        # DBH error
        return $res if !$res;

        # permission inserted
        if ( $res->{rows} ) {
            $modified = 1;
        }

        # permission is already exists
        else {
            state $q2 = $dbh->prepare(q[UPDATE "auth_user_permission" SET "enabled" = ? WHERE "user_id" = ? AND "enabled" = ? AND "permission_id" = (SELECT "id" FROM "auth_app_permission" WHERE "name" = ?)]);

            $res = $dbh->do( $q2, [ SQL_BOOL $enabled, SQL_UUID $user_id, SQL_BOOL !$enabled, $name ] );

            # DBH error
            return $res if !$res;

            # permission updated
            $modified = 1 if $res->{rows};

            $final_permissions->{$name} = 0+ !!$enabled;
        }
    }

    if ($modified) {
        return res 200, $final_permissions;
    }
    else {
        return res 204, $final_permissions;
    }
}

# TODO
sub _db_set_token_permissions ( $self, $dbh, $token_id, $permissions ) {
    return;
}

sub _remove_token ( $self, $token_id, $token_type ) {
    state $q1 = $self->{dbh}->prepare('DELETE FROM "auth_token" WHERE "id" = ? AND "type" = ?');

    my $res = $self->{dbh}->do( $q1, [ SQL_UUID $token_id, $token_type ] );

    # DBH error
    return $res if !$res;

    # not found
    return res 204 if !$res->{rows};

    P->fire_event( 'app.auth.cache', { type => $INVALIDATE_TOKEN, id => $token_id } );

    return res 200;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 99, 129, 235         | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
