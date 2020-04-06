package Pcore::App::API::Backend::Local;

use Pcore -role, -res, -sql;
use Pcore::App::API::Const qw[:ROOT_USER :INVALIDATE_TYPE :PRIVATE_TOKEN :TOKEN_TYPE];
use Pcore::Util::UUID qw[uuid_v4];
use Pcore::Util::Text qw[encode_utf8];
use Pcore::Util::Digest qw[sha3_512_bin];
use Pcore::Util::Data qw[to_b64u];

with qw[
  Pcore::App::API::Backend
  Pcore::App::API::Backend::Local::User
  Pcore::App::API::Backend::Local::UserActionToken
  Pcore::App::API::Backend::Local::UserSession
  Pcore::App::API::Backend::Local::UserToken
];

has dbh => ( required => 1 );

has auth_workers            => ( required => 1 );
has auth_argon2_time        => ( required => 1 );
has auth_argon2_memory      => ( required => 1 );
has auth_argon2_parallelism => ( required => 1 );

has _hash_cache      => ( init_arg => undef );    # InstanceOf ['Pcore::Util::Hash::LRU']
has _hash_cache_size => 10_000;                   # PositiveInt;

# INIT
sub init ($self) {
    $self->{_hash_cache} = P->hash->limited( $self->{_hash_cache_size} );

    # update schema
    $self->_db_add_schema_patch( $self->{dbh} );

    print 'Upgrading API DB schema ... ';

    say my $res = $self->{dbh}->upgrade_schema;

    return $res unless $res;

    # sync app permissions
    ( $res = $self->_sync_app_permissions ) or return $res;

    # run hash RPC
    print 'Starting API RPC node ... ';

    say $self->{app}->{node}->run_node(
        {   type      => 'Pcore::App::API::Node',
            workers   => $self->{workers},
            buildargs => {
                argon2_time        => $self->{argon2_time},
                argon2_memory      => $self->{argon2_memory},
                argon2_parallelism => $self->{argon2_parallelism},
            },
        },
    );

    $self->{app}->{node}->wait_node('Pcore::App::API::Node');

    print 'Creating root user ... ';

    my $root_password = P->random->bytes_hex(32);

    $res = $self->user_create( $ROOT_USER_NAME, $root_password, 1, undef );

    say $res . ( $res ? ", password: $root_password" : $EMPTY );

    return res 200;
}

sub _sync_app_permissions ( $self ) {
    my $permissions = $self->{app}->get_permissions;

    my $dbh = $self->{dbh};

    my $modified = 0;

    # insert permissions
    my $res = $dbh->do( [ q[INSERT INTO "app_permission"], VALUES [ map { { name => $_ } } $permissions->@* ], 'ON CONFLICT DO NOTHING' ] );

    return $res if !$res;

    $modified += $res->{rows};

    # enable permissions
    $res = $dbh->do( [ q[UPDATE "app_permission" SET "enabled" = TRUE WHERE "enabled" = FALSE AND "name"], IN $permissions ] );

    return $res if !$res;

    $modified += $res->{rows};

    # disable removed permissions
    $res = $dbh->do( [ q[UPDATE "app_permission" SET "enabled" = FALSE WHERE "enabled" = TRUE AND "name" NOT], IN $permissions ] );

    return $res if !$res;

    $modified += $res->{rows};

    if ($modified) {
        P->fire_event( 'app.api.auth.invalidate', { type => $INVALIDATE_ALL } );

        return res 200;
    }
    else {
        return res 204;
    }
}

# AUTHENTICATE
sub do_authenticate_private ( $self, $private_token ) {
    if ( $private_token->[$PRIVATE_TOKEN_TYPE] == $TOKEN_TYPE_PASSWORD ) {
        return $self->_user_password_authenticate($private_token);
    }
    elsif ( $private_token->[$PRIVATE_TOKEN_TYPE] == $TOKEN_TYPE_TOKEN ) {
        return $self->_user_token_authenticate($private_token);
    }
    elsif ( $private_token->[$PRIVATE_TOKEN_TYPE] == $TOKEN_TYPE_SESSION ) {
        return $self->_user_session_authenticate($private_token);
    }
    else {
        return res [ 400, 'Invalid token type' ];
    }
}

# HASH
sub _verify_private_token ( $self, $private_token, $hash ) {
    if ( $private_token->[$PRIVATE_TOKEN_TYPE] == $TOKEN_TYPE_PASSWORD ) {
        my $cache_id = "$hash/$private_token->[$PRIVATE_TOKEN_HASH]";

        if ( exists $self->{_hash_cache}->{$cache_id} ) {
            return $self->{_hash_cache}->{$cache_id};
        }
        else {
            my $res = $self->{app}->{node}->rpc_call( 'Pcore::App::API::Node', 'verify_hash', $private_token->[$PRIVATE_TOKEN_HASH], $hash );

            return $self->{_hash_cache}->{$cache_id} = $res->{data} ? res 200 : res [ 400, 'Invalid token' ];
        }
    }
    else {
        return sha3_512_bin( $private_token->[$PRIVATE_TOKEN_TYPE] . $private_token->[$PRIVATE_TOKEN_HASH] . $private_token->[$PRIVATE_TOKEN_ID] ) eq $hash;
    }
}

sub _generate_password_hash ( $self, $user_name_utf8, $user_password_utf8 ) {
    my $user_name_bin = encode_utf8 $user_name_utf8;

    my $user_password_bin = encode_utf8 $user_password_utf8;

    my $private_token_hash = sha3_512_bin $user_password_bin . $user_name_bin;

    my $res = $self->{app}->{node}->rpc_call( 'Pcore::App::API::Node', 'create_hash', $private_token_hash );

    return $res if !$res;

    return res 200, { hash => $res->{data} };
}

sub _generate_token ( $self, $token_type ) {
    my $token_id = uuid_v4;

    my $rand = P->random->bytes(32);

    my $token_bin = $token_id->bin . pack( 'C', $token_type ) . $rand;

    my $private_token_hash = sha3_512_bin $rand;

    return res 200,
      { id         => $token_id->str,
        token      => to_b64u $token_bin,
        token_type => $token_type,
        hash       => sha3_512_bin $token_type . $private_token_hash . $token_id->str,
      };
}

sub _return_auth ( $self, $private_token, $user_id, $user_name ) {
    my $auth = {
        private_token => $private_token,
        user_id       => $user_id,
        user_name     => $user_name,
        permissions   => {},
    };

    my $permissions;

    # get token permissions
    if ( $private_token->[$PRIVATE_TOKEN_TYPE] == $TOKEN_TYPE_TOKEN ) {
        $permissions = $self->user_token_get_permissions( $private_token->[$PRIVATE_TOKEN_ID] );
    }

    # get user permissions, session tokens inherit user permissions
    else {
        $permissions = $self->user_get_permissions($user_id);
    }

    # get permissions error
    return $permissions if !$permissions;

    $auth->{permissions} = $permissions->{data};

    return res 200, $auth;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 |                      | Subroutines::ProhibitUnusedPrivateSubroutines                                                                  |
## |      | 126                  | * Private subroutine/method '_verify_private_token' declared but not used                                      |
## |      | 144                  | * Private subroutine/method '_generate_password_hash' declared but not used                                    |
## |      | 158                  | * Private subroutine/method '_generate_token' declared but not used                                            |
## |      | 175                  | * Private subroutine/method '_return_auth' declared but not used                                               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 144, 175             | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
