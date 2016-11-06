package Pcore::App::API::Backend::Local::sqlite::User;

use Pcore -role, -promise, -status;
use Pcore::App::API qw[:CONST];
use Pcore::Util::UUID qw[uuid_str];
use Pcore::Util::Text qw[encode_utf8];

# TODO tags
sub _auth_user_password ( $self, $source_app_instance_id, $user_name_utf8, $private_token, $cb ) {
    state $q1 = <<'SQL';
        SELECT
            api_app_role.name AS app_role_name
        FROM
            api_app_instance,
            api_app_role,
            api_user_permission
        WHERE
            api_app_instance.id = ?                                                      --- source app_instance_id
            AND api_app_role.app_id = api_app_instance.app_id                            --- link source_app_instance_role to source_app
            AND api_app_role.id = api_user_permission.app_role_id                           --- link app_role to user_permissions
            AND api_user_permission.user_id = ?
SQL

    # get user
    my $user = $self->dbh->selectrow( q[SELECT id, hash, enabled FROM api_user WHERE name = ?], [$user_name_utf8] );

    # user not found
    if ( !$user ) {
        $cb->( status [ 404, 'User not found' ] );

        return;
    }

    # user is disabled
    if ( !$user->{enabled} ) {
        $cb->( status [ 404, 'User disabled' ] );

        return;
    }

    my $get_permissions = sub {
        my $user_id = $user->{id};

        my $auth = {
            token_type => $TOKEN_TYPE_USER_PASSWORD,
            token_id   => $user_name_utf8,

            is_user   => 1,
            is_root   => $user_name_utf8 eq 'root',
            user_id   => $user_id,
            user_name => $user_name_utf8,

            is_app          => 0,
            app_id          => undef,
            app_instance_id => undef,
        };

        my $tags = {};

        # root user
        if ( $auth->{is_root} ) {
            $auth->{permissions} = {};
        }

        # non-root user
        else {

            # get permissions
            if ( my $roles = $self->dbh->selectall( $q1, [ $source_app_instance_id, $user_id ] ) ) {
                $auth->{permissions} = { map { $_->{app_role_name} => 1 } $roles->@* };
            }
            else {
                $auth->{permissions} = {};
            }
        }

        $cb->( status 200, { auth => $auth, tags => $tags } );

        return;
    };

    if ($private_token) {

        # verify token
        $self->_verify_token_hash(
            $private_token,
            $user->{hash},
            encode_utf8( $user->{id} ),
            sub ($status) {

                # token is valid
                if ($status) {
                    $get_permissions->();
                }

                # token is invalid
                else {
                    $cb->($status);
                }

                return;
            }
        );
    }
    else {
        $get_permissions->();
    }

    return;
}

sub get_users ( $self, $cb ) {
    if ( my $users = $self->dbh->selectall(q[SELECT * FROM api_user]) ) {
        for my $row ( $users->@* ) {
            delete $row->{hash};
        }

        $cb->( status 200, users => $users );
    }
    else {
        $cb->( status 500 );
    }

    return;
}

sub get_user ( $self, $user_id, $cb ) {

    # $user_id is id
    if ( $user_id =~ /\A[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}\z/sm ) {
        if ( my $user = $self->dbh->selectrow( q[SELECT * FROM api_user WHERE id = ?], [$user_id] ) ) {
            delete $user->{hash};

            $cb->( status 200, $user );
        }
        else {

            # user not found
            $cb->( status [ 404, 'User not found' ] );
        }
    }

    # $user_id is name
    else {
        if ( my $user = $self->dbh->selectrow( q[SELECT * FROM api_user WHERE name = ?], [$user_id] ) ) {
            delete $user->{hash};

            $cb->( status 200, $user );
        }
        else {

            # user not found
            $cb->( status [ 404, 'User not found' ] );
        }
    }

    return;
}

sub create_root_user ( $self, $cb ) {
    $self->get_user(
        'root',
        sub ($user) {

            # root user already exists
            if ($user) {
                $cb->( status 304 );
            }
            else {
                my $user_id = uuid_str;

                my $root_password = P->random->bytes_hex(32);

                $self->_generate_user_password_hash(
                    'root',
                    $root_password,
                    $user_id,
                    sub ( $password_hash ) {

                        # password hash generation error
                        if ( !$password_hash ) {
                            $cb->($password_hash);
                        }

                        # password hash generated
                        else {
                            my $created = $self->dbh->do( q[INSERT OR IGNORE INTO api_user (id, name, enabled, created_ts, hash) VALUES (?, ?, 1, ?, ?)], [ $user_id, 'root', time, $password_hash->{result}->{hash} ] );

                            if ( !$created ) {
                                $cb->( status [ 500, 'Error creating root user' ] );
                            }
                            else {
                                $cb->( status 200, { root_password => $root_password } );
                            }
                        }

                        return;
                    }
                );
            }

            return;
        }
    );

    return;
}

sub create_user ( $self, $base_user_id, $user_name, $password, $enabled, $permissions, $cb ) {
    if ( $user_name eq 'root' ) {
        $cb->( status [ 400, 'User name is not valid' ] );

        return;
    }

    # validate user name
    if ( !$self->{app}->{api}->validate_name($user_name) || $user_name eq 'root' ) {
        $cb->( status [ 400, 'User name is not valid' ] );

        return;
    }

    if ( $self->dbh->selectrow( q[SELECT id FROM api_user WHERE name = ?], [$user_name] ) ) {
        $cb->( status [ 400, 'User name already exists' ] );

        return;
    }

    # resolve permissions
    $self->resolve_app_roles(
        $permissions,
        sub ($roles) {
            if ( !$roles ) {
                $cb->($roles);
            }
            else {

                # get base user
                $self->get_user(
                    $base_user_id,
                    sub ($base_user) {

                        # base user get error
                        if ( !$base_user ) {
                            $cb->($base_user_id);
                        }

                        # base user found
                        else {

                            my $create_user = sub {
                                my $user_id = uuid_str;

                                # generate user password hash
                                $self->_generate_user_password_hash(
                                    $user_name,
                                    $password,
                                    $user_id,
                                    sub ( $password_hash ) {

                                        # password hash generation error
                                        if ( !$password_hash ) {
                                            $cb->($password_hash);
                                        }

                                        # password hash generated
                                        else {
                                            my $dbh = $self->dbh;

                                            $dbh->begin_work;

                                            my $created = $dbh->do( q[INSERT OR IGNORE INTO api_user (id, name, enabled, created_ts, hash) VALUES (?, ?, ?, ?, ?)], [ $user_id, $user_name, $enabled, time, $password_hash->{result}->{hash} ] );

                                            # user creation error
                                            if ( !$created ) {
                                                $dbh->rollback;

                                                $cb->( status [ 500, 'User creation error' ] );
                                            }

                                            # user created
                                            else {

                                                # add user permissions
                                                for my $role_id ( keys $roles->{result}->%* ) {
                                                    my $user_permission_id = uuid_str;

                                                    # create permission
                                                    my $permission_created = $dbh->do( q[INSERT OR IGNORE INTO api_user_permission (id, user_id, app_role_id) VALUES (?, ?, ?)], [ $user_permission_id, $user_id, $role_id ] );

                                                    # permisison create error
                                                    if ( !$permission_created ) {
                                                        $dbh->rollback;

                                                        $cb->( status [ 500, 'User creation error' ] );

                                                        return;
                                                    }
                                                }

                                                # permissions created
                                                $dbh->commit;

                                                $self->get_user(
                                                    $user_id,
                                                    sub ($user) {
                                                        $cb->($user);

                                                        return;
                                                    }
                                                );
                                            }
                                        }

                                        return;
                                    }
                                );

                                return;
                            };

                            # base user is root
                            if ( $base_user->{result}->{name} eq 'root' ) {
                                $create_user->();
                            }

                            # base user is not root
                            else {

                                # get base user permissions
                                $self->get_user_permissions(
                                    $base_user->{result}->{id},
                                    sub ($base_user_permissions) {

                                        # base user permissions get error
                                        if ( !$base_user_permissions ) {
                                            $cb->($base_user_permissions);
                                        }

                                        # base user permissions get ok
                                        else {

                                            # compare base user permissions
                                            for my $role_id ( keys $roles->{result}->%* ) {

                                                # base user permission not exists
                                                if ( !$base_user_permissions->{result}->{$role_id}->{user_permission_id} ) {
                                                    $cb->( status [ 400, 'Permissions error' ] );

                                                    return;
                                                }
                                            }

                                            $create_user->();
                                        }

                                        return;
                                    }
                                );
                            }
                        }

                        return;
                    }
                );
            }

            return;
        }
    );

    return;
}

sub set_user_password ( $self, $user_id, $user_password_bin, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $user ) {

            # get user error
            if ( !$user ) {
                $cb->($user);
            }

            # get user ok
            else {
                $self->_generate_user_password_hash(
                    $user->{result}->{name},
                    $user_password_bin,
                    encode_utf8( $user->{result}->{id} ),
                    sub ( $password_hash ) {

                        # password hash genereation error
                        if ( !$password_hash ) {
                            $cb->($password_hash);
                        }

                        # password hash generated
                        else {
                            my $updated = $self->dbh->do( q[UPDATE api_user SET hash = ? WHERE id = ?], [ $password_hash->{result}->{hash}, $user->{result}->{id} ] );

                            if ( !$updated ) {
                                $cb->( status [ 500, 'Error setting user password' ] );
                            }
                            else {
                                $cb->( status 200 );
                            }
                        }

                        return;
                    }
                );
            }

            return;
        }
    );

    return;
}

sub set_user_enabled ( $self, $user_id, $enabled, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $user ) {
            if ( !$user ) {
                $cb->($user);

                return;
            }

            if ( !!$enabled ^ $user->{result}->{enabled} ) {
                if ( $self->dbh->do( q[UPDATE OR IGNORE api_user SET enabled = ? WHERE id = ?], [ !!$enabled, $user->{result}->{id} ] ) ) {
                    $cb->( status 200 );
                }
                else {
                    $cb->( status [ 500, 'Error set user enabled' ] );
                }
            }
            else {

                # not modified
                $cb->( status 304 );
            }

            return;
        }
    );

    return;
}

# USER PERMISSIONS
# return all user permissions, indexed by app role id
sub get_user_permissions ( $self, $user_id, $cb ) {
    my $permissions = $self->dbh->selectall(
        <<'SQL',
            SELECT
                api_user_permission.id AS user_permission_id,
                api_app_role.id AS app_role_id,
                api_app_role.name AS app_role_name,
                api_app_role.desc AS app_role_desc,
                api_app.name AS app_name,
                api_app.desc AS app_desc
            FROM
                api_app,
                api_app_role
                LEFT JOIN api_user_permission ON
                    api_user_permission.app_role_id = api_app_role.id
                    AND api_user_permission.user_id = ?
            WHERE
                api_app.id = api_app_role.app_id
SQL
        [$user_id]
    );

    if ( !$permissions ) {
        $cb->( status 200, {} );
    }
    else {

        # index permissions by app_role_id
        $permissions = { map { $_->{app_role_id} => $_ } $permissions->@* };

        $cb->( status 200, $permissions );
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
## |    3 | 9, 209, 375          | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 9                    | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_auth_user_password' declared but   |
## |      |                      | not used                                                                                                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 130                  | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 209                  | Subroutines::ProhibitExcessComplexity - Subroutine "create_user" with high complexity score (21)               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 292, 347             | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::sqlite::User

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
