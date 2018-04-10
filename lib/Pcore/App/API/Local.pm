package Pcore::App::API::Local;

use Pcore -const, -role, -result, -sql;
use Pcore::App::API qw[:CONST];
use Pcore::Util::Data qw[to_b64_url];
use Pcore::Util::Digest qw[sha3_512];
use Pcore::Util::Text qw[encode_utf8];
use Pcore::Util::UUID qw[uuid_v4 looks_like_uuid];

with qw[Pcore::App::API];

has dbh         => ( is => 'ro', isa => InstanceOf ['Pcore::Handle::DBI'],         init_arg => undef );
has _hash_rpc   => ( is => 'ro', isa => InstanceOf ['Pcore::Util::PM::RPC'],       init_arg => undef );
has _hash_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Hash::RandKey'], init_arg => undef );
has _hash_cache_size => ( is => 'ro', isa => PositiveInt, default => 10_000 );

sub init ( $self ) {
    $self->{_hash_cache} = P->hash->limited( $self->{_hash_cache_size} );

    # create DBH
    $self->{dbh} = P->handle( $self->{app}->{app_cfg}->{api}->{connect} );

    # update schema
    $self->_db_add_schema_patch( $self->{dbh} );

    print 'Upgrading API DB schema ... ';

    say my $res = $self->{dbh}->upgrade_schema;

    return $res unless $res;

    my $roles = do {
        no strict qw[refs];

        ${ ref( $self->{app} ) . '::APP_API_ROLES' };
    };

    # add api roles
    ( $res = $self->_db_add_roles( $self->{dbh}, $roles ) ) || return $res;

    # run hash RPC
    print 'Starting API RPC ... ';

    P->pm->run_rpc(
        'Pcore::App::API::RPC::Hash',
        workers   => $self->{app}->{app_cfg}->{api}->{rpc}->{workers},
        buildargs => $self->{app}->{app_cfg}->{api}->{rpc}->{argon},
        on_ready  => Coro::rouse_cb,
    );

    $self->{_hash_rpc} = Coro::rouse_wait;

    $self->{_hash_rpc}->connect_rpc( on_connect => Coro::rouse_cb );

    Coro::rouse_wait;

    say 'done';

    print 'Creating root user ... ';

    my $root_password = P->random->bytes_hex(32);

    $res = $self->create_user( 'root', $root_password, 1, undef );

    say $res . ( $res ? ", password: $root_password" : q[] );

    return result 200;
}

# AUTHENTICATE
sub do_authenticate_private ( $self, $private_token, $cb ) {
    if ( $private_token->[0] == $TOKEN_TYPE_USER_PASSWORD ) {
        $self->_auth_user_password( $private_token, $cb );
    }
    elsif ( $private_token->[0] == $TOKEN_TYPE_USER_TOKEN ) {
        $self->_auth_user_token( $private_token, $cb );
    }
    elsif ( $private_token->[0] == $TOKEN_TYPE_USER_SESSION ) {
        $self->_auth_user_token( $private_token, $cb );
    }
    else {
        $cb->( result [ 400, 'Invalid token type' ] );
    }

    return;
}

# TOKENS / HASH GENERATORS
sub validate_name ( $self, $name ) {

    # name looks like UUID string
    return if looks_like_uuid $name;

    return if $name =~ /[^[:alnum:]_@.-]/smi;

    return 1;
}

sub _verify_token_hash ( $self, $private_token_hash, $hash, $cb ) {
    my $cache_id = "$hash/$private_token_hash";

    if ( exists $self->{_hash_cache}->{$cache_id} ) {
        $cb->( $self->{_hash_cache}->{$cache_id} );
    }
    else {
        $self->_hash_rpc->rpc_call(
            'verify_hash',
            $private_token_hash,
            $hash,
            sub ( $res ) {
                $cb->( $self->{_hash_cache}->{$cache_id} = $res->{match} ? result 200 : result [ 400, 'Invalid token' ] );

                return;
            }
        );
    }

    return;
}

sub _generate_user_password_hash ( $self, $user_name_utf8, $user_password_utf8 ) {
    my $user_name_bin = encode_utf8 $user_name_utf8;

    my $user_password_bin = encode_utf8 $user_password_utf8;

    my $private_token_hash = sha3_512 $user_password_bin . $user_name_bin;

    $self->_hash_rpc->rpc_call( 'create_hash', $private_token_hash, Coro::rouse_cb );

    my $res = Coro::rouse_wait;

    if ( !$res ) {
        return $res;
    }
    else {
        return result 200, { hash => $res->{hash} };
    }
}

sub _generate_token ( $self, $token_type ) {
    my $token_id = uuid_v4;

    my $public_token = to_b64_url pack( 'C', $token_type ) . $token_id->bin . P->random->bytes(32);

    my $private_token_hash = sha3_512 $public_token;

    $self->_hash_rpc->rpc_call( 'create_hash', $private_token_hash, Coro::rouse_cb );

    my $res = Coro::rouse_wait;

    if ( !$res ) {
        return $res;
    }
    else {
        return result 200, { id => $token_id->str, token => $public_token, hash => $res->{hash} };
    }
}

sub _return_auth ( $self, $private_token, $user_id, $user_name, $cb ) {
    my $auth = {
        private_token => $private_token,

        is_root   => $user_name eq 'root' ? 1 : 0,
        user_id   => $user_id,
        user_name => $user_name,

        permissions => {},
    };

    # is a root user
    if ( $auth->{is_root} ) {
        $cb->( result 200, $auth );
    }
    else {
        if ( $private_token->[0] == $TOKEN_TYPE_USER_TOKEN ) {
            my $res = $self->_db_get_user_token_permissions( $self->{dbh}, $private_token->[1] );

            if ( !$res ) {
                $cb->( result 500 );
            }
            else {
                $auth->{permissions} = { map { $_->{role_name} => 1 } $res->@* };

                $cb->( result 200, $auth );
            }
        }
        else {
            my $res = $self->_db_get_user_permissions( $self->{dbh}, $user_id );

            if ( !$res ) {
                $cb->( result 500 );
            }
            else {
                $auth->{permissions} = { map { $_->{role_name} => 1 } $res->@* };

                $cb->( result 200, $auth );
            }
        }
    }

    return;
}

# USER
sub _auth_user_password ( $self, $private_token, $cb ) {

    # get user
    my $user = $self->{dbh}->selectrow( q[SELECT "id", "hash", "enabled" FROM "api_user" WHERE "name" = ?], [ $private_token->[1] ] );

    # user not found
    if ( !$user->@* ) {
        $cb->( result [ 404, 'User not found' ] );

        return;
    }

    # user is disabled
    if ( !$user->{enabled} ) {
        $cb->( result [ 404, 'User is disabled' ] );

        return;
    }

    # verify token
    $self->_verify_token_hash(
        $private_token->[2],
        $user->{hash},
        sub ($status) {

            # token is invalid
            if ( !$status ) {
                $cb->($status);
            }

            # token is valid
            else {
                $self->_return_auth( $private_token, $user->{id}, $private_token->[1], $cb );
            }

            return;
        }
    );

    return;
}

sub create_user ( $self, $user_name, $password, $enabled, $permissions ) {

    # validate user name
    if ( !$self->validate_name($user_name) ) {
        return result [ 400, 'User name is not valid' ];
    }

    state $on_finish = sub ( $dbh, $res ) {
        if ( !$res ) {
            my $res1 = $dbh->rollback;

            return $res;
        }
        else {
            my $res1 = $dbh->commit;

            # error committing transaction
            if ( !$res1 ) {
                return result 500;
            }
            else {
                return $res;
            }
        }

        return;
    };

    # start transaction
    my ( $dbh, $res ) = $self->{dbh}->begin_work;

    # failed to start transaction
    return result 500 if !$res;

    # check, that user is not exists
    my $user = $self->_db_get_user( $dbh, $user_name );

    # user already exists
    return $on_finish->( $dbh, result [ 400, 'User name already exists' ] ) if $user;

    # generate user password hash
    $res = $self->_generate_user_password_hash( $user_name, $password );

    # error generating hash
    return $on_finish->( $dbh, result 500 ) if !$res;

    # insert user
    $user = $self->_db_create_user( $dbh, $user_name, $res->{data}->{hash}, $enabled );

    # failed to insert user
    return $on_finish->( $dbh, result 500 ) if !$user;

    # set user permissions
    $res = $self->_set_user_permissions( $dbh, $user->{data}->{id}, $permissions );

    return $on_finish->( $dbh, $res ) if !$res;

    return $on_finish->( $dbh, $user );
}

sub get_users ( $self, $cb ) {
    return $self->_db_get_users( $self->{dbh} );
}

sub get_user ( $self, $user_id ) {
    return $self->_db_get_user( $self->{dbh}, $user_id );
}

sub set_user_permissions ( $self, $user_id, $permissions, $cb ) {

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    if ( !$user ) {
        $cb->($user);
    }
    else {

        # begin transaction
        my ( $dbh, $res ) = $self->{dbh}->begin_work;

        # error, strating transaction
        if ( !$res ) {
            $cb->( result 500 );
        }
        else {
            $res = $self->_set_user_permissions( $dbh, $user->{data}->{id}, $permissions );

            # sql error
            if ( !$res ) {
                my $res1 = $dbh->rollback;

                $cb->($res);
            }
            else {
                my $res1 = $dbh->commit;

                # commit error
                if ( !$res1 ) {
                    $cb->( result 500 );
                }

                # commit ok
                else {

                    # fire event if user permissions was changed
                    P->fire_event('APP.API.AUTH') if $res == 200;

                    $cb->($res);
                }
            }
        }
    }

    return;
}

sub _set_user_permissions ( $self, $dbh, $user_id, $permissions ) {
    if ( !$permissions || !$permissions->@* ) {
        return result 204;    # not modified
    }

    my $roles = $self->_db_get_roles($dbh);

    if ( !$roles ) {
        return $roles;
    }
    else {
        my $role_name_idx = { map { $_->{name} => $_->{id} } values $roles->%* };

        my $roles_ids;

        for my $perm ( $permissions->@* ) {

            # resolve role id
            my $perm_role_id = looks_like_uuid $perm ? $roles->{data}->{$perm}->{id} : $role_name_idx->{$perm};

            # permission role wasn't found
            if ( !$perm_role_id ) {
                return result [ 400, qq[role "$perm" is invlalid] ];
            }

            push $roles_ids->@*, $perm_role_id;
        }

        return $self->_db_set_user_permissions( $dbh, $user_id, $roles_ids );
    }
}

sub set_user_password ( $self, $user_id, $password, $cb ) {

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    if ( !$user ) {
        $cb->($user);
    }
    else {
        $self->_generate_user_password_hash(
            $user->{data}->{name},
            $password,
            sub ( $password_hash ) {

                # password hash genereation error
                if ( !$password_hash ) {
                    $cb->( result 500 );
                }

                # password hash generated
                else {
                    my $res = $self->{dbh}->do( q[UPDATE "api_user" SET "hash" = ? WHERE "id" = ?], [ SQL_BYTEA $password_hash->{data}->{hash}, SQL_UUID $user->{data}->{id} ] );

                    if ( !$res ) {
                        $cb->( result 500 );
                    }
                    else {
                        if ( !$res->rows ) {
                            $cb->( result 500 );
                        }
                        else {

                            # fire AUTH event if user password was changed
                            P->fire_event('APP.API.AUTH');

                            $cb->( result 200 );
                        }
                    }
                }

                return;
            }
        );
    }

    return;
}

sub set_user_enabled ( $self, $user_id, $enabled, $cb ) {

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    if ( !$user ) {
        $cb->($user);
    }
    else {
        $enabled = 0+ !!$enabled;

        if ( $enabled ^ $user->{data}->{enabled} ) {
            my $res = $self->{dbh}->do( q[UPDATE "api_user" SET "enabled" = ? WHERE "id" = ?], [ SQL_BOOL $enabled, SQL_UUID $user->{data}->{id} ] );

            if ( !$res ) {
                $cb->( result 500 );
            }
            elsif ( !$res->rows ) {
                $cb->( result 500 );
            }
            else {

                # fire AUTH event if user was disabled
                P->fire_event('APP.API.AUTH') if !$enabled;

                $cb->( result 200, { enabled => $enabled } );
            }
        }
        else {

            # not modified
            $cb->( result 204, { enabled => $enabled } );
        }
    }

    return;
}

# USER TOKEN
sub _auth_user_token ( $self, $private_token, $cb ) {

    # get user token
    my $user_token = $self->{dbh}->selectrow(
        <<'SQL',
            SELECT
                "api_user"."id" AS "user_id",
                "api_user"."name" AS "user_name",
                "api_user"."enabled" AS "user_enabled",
                "api_user_token"."hash" AS "user_token_hash"
            FROM
                "api_user",
                "api_user_token"
            WHERE
                "api_user"."id" = "api_user_token"."user_id"
                AND "api_user_token"."id" = ?
SQL
        [ SQL_UUID $private_token->[1] ]
    );

    # user is disabled
    if ( !$user_token->{user_enabled} ) {
        $cb->( result 404 );

        return;
    }

    # verify token
    $self->_verify_token_hash(
        $private_token->[2],
        $user_token->{user_token_hash},
        sub ($status) {

            # token is not valid
            if ( !$status ) {
                $cb->($status);
            }

            # token is valid
            else {
                $self->_return_auth( $private_token, $user_token->{user_id}, $user_token->{user_name}, $cb );
            }

            return;
        }
    );

    return;
}

sub create_user_token ( $self, $user_id, $desc, $permissions, $cb ) {
    my $type = $TOKEN_TYPE_USER_TOKEN;

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    if ( !$user ) {
        $cb->($user);
    }
    else {

        # generate user token
        $self->_generate_token(
            $type,
            sub ($token) {

                # token generation error
                if ( !$token ) {
                    $cb->($token);
                }

                # token geneerated
                else {

                    # get user permissions
                    my $user_permissions = $self->_db_get_user_permissions( $self->{dbh}, $user->{data}->{id} );

                    # error
                    if ( !$user_permissions ) {
                        $cb->($user_permissions);

                        return;
                    }

                    # find user permissions id's
                    if ( defined $permissions ) {

                        # create index by role name
                        my $idx = { map { $_ => 1 } $permissions->@* };

                        $user_permissions = [ grep { exists $idx->{ $_->{role_name} } } $user_permissions->@* ];

                        # some permissions are invalid or not allowed
                        if ( $permissions->@* != $user_permissions->@* ) {
                            $cb->( result 500 );

                            return;
                        }
                    }

                    # begin transaction
                    my ( $dbh, $res ) = $self->{dbh}->begin_work;

                    # error
                    if ( !$res ) {
                        $cb->($res);

                        return;
                    }

                    my $on_finish = sub ($res) {
                        if ( !$res ) {
                            $res = $dbh->rollback;

                            $cb->( result 500 );
                        }
                        else {
                            $res = $dbh->commit;

                            if ( !$res ) {
                                $cb->( result 500 );
                            }
                            else {
                                $cb->(
                                    result 200,
                                    {   id    => $token->{data}->{id},
                                        type  => $type,
                                        token => $token->{data}->{token},
                                    }
                                );
                            }
                        }

                        return;
                    };

                    # insert token
                    $res = $dbh->do( 'INSERT INTO "api_user_token" ("id", "type", "user_id", "hash", "desc" ) VALUES (?, ?, ?, ?, ?)', [ SQL_UUID $token->{data}->{id}, $type, SQL_UUID $user->{data}->{id}, SQL_BYTEA $token->{data}->{hash}, $desc ] );

                    if ( !$res ) {
                        $on_finish->($res);
                    }
                    else {

                        # no permissions to insert, eg: root user
                        if ( !$user_permissions->@* ) {
                            $on_finish->($res);

                            return;
                        }

                        # insert user token permissions
                        $res = $dbh->do( [ q[INSERT INTO "api_user_token_permission"], VALUES [ map { { user_token_id => SQL_UUID $token->{data}->{id}, user_permission_id => SQL_UUID $_->{id} } } $user_permissions->{data}->@* ] ] );

                        $on_finish->($res);
                    }
                }

                return;
            }
        );
    }

    return;
}

sub remove_user_token ( $self, $user_token_id, $cb ) {
    my $res = $self->{dbh}->do( 'DELETE FROM "api_user_token" WHERE "id" = ? AND "type" = ?', [ SQL_UUID $user_token_id, $TOKEN_TYPE_USER_TOKEN ] );

    if ( !$res ) {
        $cb->( result 500 );
    }
    elsif ( !$res->rows ) {
        $cb->( result 204 );    # not found
    }
    else {
        P->fire_event('APP.API.AUTH');

        $cb->( result 200 );
    }

    return;
}

# USER SESSION
sub create_user_session ( $self, $user_id ) {
    my $type = $TOKEN_TYPE_USER_SESSION;

    # resolve user
    my $user = $self->_db_get_user( $self->{dbh}, $user_id );

    # user wasn't found
    if ( !$user ) {
        return $user;
    }
    else {

        # generate session token
        my $token = $self->_generate_token($type);

        # token generation error
        if ( !$token ) {
            return $token;
        }

        # token geneerated
        else {
            my $res = $self->{dbh}->do( 'INSERT INTO "api_user_token" ("id", "type", "user_id", "hash") VALUES (?, ?, ?, ?)', [ SQL_UUID $token->{data}->{id}, $type, SQL_UUID $user->{data}->{id}, SQL_BYTEA $token->{data}->{hash} ] );

            if ( !$res->rows ) {
                return result 500;
            }
            else {
                return result 200,
                  { id    => $token->{data}->{id},
                    type  => $type,
                    token => $token->{data}->{token},
                  };
            }
        }
    }
}

sub remove_user_session ( $self, $user_sid ) {
    my $res = $self->{dbh}->do( 'DELETE FROM "api_user_token" WHERE "id" = ? AND "type" = ?', [ SQL_UUID $user_sid, $TOKEN_TYPE_USER_SESSION ] );

    if ( !$res ) {
        return result 500;
    }
    elsif ( !$res->rows ) {
        return result 204;    # not found
    }
    else {
        P->fire_event('APP.API.AUTH');

        return result 200;
    }

    return;
}

# DB METHODS
sub _db_get_users ( $self, $dbh ) {
    return $dbh->selectall(q[SELECT "id", "name", "enabled", "created" FROM "api_user"]);
}

sub _db_get_user ( $self, $dbh, $user_id ) {
    my $is_uuid = looks_like_uuid $user_id;

    my $user = $dbh->selectrow( qq[SELECT "id", "name", "enabled", "created" FROM "api_user" WHERE "@{[$is_uuid ? 'id' : 'name']}" = ?], $is_uuid ? [ SQL_UUID $user_id ] : [$user_id] );

    # query error
    if ( !$user ) {
        return result 500;
    }

    # user not found
    elsif ( !$user->@* ) {
        return result [ 404, 'User not found' ];
    }
    else {
        return result 200, $user;
    }

    return;
}

sub _db_get_roles ( $self, $dbh ) {
    return $dbh->selectall( q[SELECT * FROM "api_role"], key_field => 'id' );
}

sub _db_get_user_permissions ( $self, $dbh, $user_id ) {
    return $dbh->selectall(
        <<'SQL',
            SELECT
                "api_user_permission"."id" AS "id",
                "api_role"."id" AS "role_id",
                "api_role"."name" AS "role_name"
            FROM
                "api_user_permission",
                "api_role"
            WHERE
                "api_user_permission"."role_id" = "api_role"."id"
                AND "api_user_permission"."user_id" = ?
SQL
        [ SQL_UUID $user_id ]
    );
}

sub _db_get_user_token_permissions ( $self, $dbh, $user_token_id ) {
    return $dbh->selectall(
        <<'SQL',
            SELECT
                "api_user_token_permission"."id" AS "id",
                "api_role"."id" AS "role_id",
                "api_role"."name" AS "role_name"
            FROM
                "api_user_token_permission",
                "api_user_permission",
                "api_role"
            WHERE
                "api_user_token_permission"."user_permission_id" = "api_user_permission"."id"
                AND "api_user_permission"."role_id" = "api_role"."id"
                AND "api_user_token_permission"."user_token_id" = ?
SQL
        [ SQL_UUID $user_token_id ]
    );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 99, 121, 159, 247,   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 536                  |                                                                                                                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
