package Pcore::App::API::Backend::Local::sqlite::UserToken;

use Pcore -role, -promise, -status;
use Pcore::Util::UUID qw[uuid_str];

sub _auth_user_token ( $self, $source_app_instance_id, $user_token_id, $private_token, $cb ) {
    state $sql1 = <<'SQL';
        SELECT
            api_user.id AS user_id,
            api_user.name AS user_name,
            api_user.enabled AS user_enabled,
            api_user_token.hash,
            api_user_token.enabled AS user_token_enabled
        FROM
            api_user,
            api_user_token
        WHERE
            api_user_token.id = ?
            AND api_user_token.user_id = api_user.id
SQL

    state $sql2 = <<'SQL';
        SELECT
            api_app_role.name AS source_app_role_name
        FROM
            api_app_instance,
            api_app_role,
            api_user_permissions,
            api_user_token_permissions
        WHERE
            api_app_instance.id = ?                                                         --- source app_instance_id
            AND api_app_role.app_id = api_app_instance.app_id                               --- link source_app_instance_role to source_app
            AND api_app_role.enabled = 1                                                    --- source_app_role must be enabled

            AND api_app_role.id = api_user_permissions.role_id                              --- link app_role to user_permissions
            AND api_user_permissions.enabled = 1                                            --- user permission must be enabled

            AND api_user_permissions.id = api_user_token_permissions.user_permissions_id    --- link user_token_permissions to user_permissions
            AND api_user_token_permissions.user_token_id = ?                                --- link user_token_permissions to user_token
SQL

    # get user token by token id
    my $res = $self->dbh->selectrow( $sql1, [$user_token_id] );

    # user token not found
    if ( !$res ) {
        $cb->( status [ 404, 'User token not found' ] );

        return;
    }

    my $user_id = $res->{user_id};

    my $continue = sub {
        my $auth = {
            user_id       => $user_id,
            user_name     => $res->{user_name},
            user_token_id => $user_token_id,
            enabled       => $res->{user_enabled} && $res->{user_token_enabled},
        };

        my $tags = {
            user_id       => $user_id,
            user_token_id => $user_token_id,
        };

        # get permissions
        if ( my $roles = $self->dbh->selectall( $sql2, [ $source_app_instance_id, $user_token_id ] ) ) {
            for my $row ( $roles->@* ) {
                $auth->{permissions}->{ $row->{source_app_role_name} } = 1;
            }
        }
        else {
            $auth->{permissions} = {};
        }

        $cb->( status 200, auth => $auth, tags => $tags );

        return;
    };

    if ($private_token) {

        # verify token
        $self->_verify_token_hash(
            $private_token . $user_id,
            $res->{hash},
            sub ($status) {

                # token valid
                if ($status) {
                    $continue->();
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
        $continue->();
    }

    return;
}

sub get_user_token ( $self, $user_token_id, $cb ) {
    if ( my $user_token = $self->dbh->selectrow( q[SELECT * FROM api_user_token WHERE id = ?], [$user_token_id] ) ) {
        delete $user_token->{hash};

        $cb->( status 200, user_token => $user_token );
    }
    else {

        # user token not found
        $cb->( status [ 404, 'User token not found' ] );
    }

    return;
}

sub create_user_token ( $self, $user_id, $desc, $permissions, $cb ) {

    # get user
    $self->get_user(
        $user_id,
        sub ($user) {

            # get user error
            if ( !$user ) {
                $cb->($user);
            }

            # get user ok
            else {

                # root user can't have token
                if ( $user->{result}->{name} eq 'root' ) {
                    $cb->( status [ 400, 'Error creation token for root user' ] );
                }
                else {

                    # resolve repmisisons
                    $self->resolve_app_roles(
                        $permissions,
                        sub ($roles) {

                            # error resolving permisions
                            if ( !$roles ) {
                                $cb->($roles);
                            }

                            # permissions resolved
                            else {

                                # get user permissions
                                $self->get_user_permissions(
                                    $user->{result}->{id},
                                    sub ($user_permissions) {

                                        # user permissions get error
                                        if ( !$user_permissions ) {
                                            $cb->($user_permissions);
                                        }

                                        # user permissions ok
                                        else {

                                            # compare token and user permissions
                                            for my $role_id ( keys $roles->{result}->%* ) {

                                                # user permission is not set
                                                if ( !$user_permissions->{result}->{$role_id}->{user_permission_id} ) {
                                                    $cb->( status [ 400, q[Invalid user token permissions] ] );

                                                    return;
                                                }
                                            }

                                            # generate user token
                                            $self->_generate_user_token(
                                                $user->{result}->{id},
                                                sub ($user_token) {

                                                    # user token generation error
                                                    if ( !$user_token ) {
                                                        $cb->($user_token);
                                                    }

                                                    # user token generated
                                                    else {
                                                        my $dbh = $self->dbh;

                                                        $dbh->begin_work;

                                                        # insert user token
                                                        my $token_created = $dbh->do( q[INSERT OR IGNORE INTO api_user_token (id, user_id, desc, created_ts, hash) VALUES (?, ?, ?, ?, ?)], [ $user_token->{result}->{id}, $user->{result}->{id}, $desc // q[], time, $user_token->{result}->{hash} ] );

                                                        if ( !$token_created ) {
                                                            $dbh->rollback;

                                                            $cb->( status [ 500, 'User token creation error' ] );
                                                        }

                                                        # create user token permissions
                                                        else {
                                                            for my $role_id ( keys $roles->{result}->%* ) {

                                                                # create user permission
                                                                my $permission_created = $dbh->do( q[INSERT INTO api_user_token_permission (id, user_token_id, user_permission_id) VALUES (?, ?, ?)], [ uuid_str, $user_token->{result}->{id}, $user_permissions->{result}->{$role_id}->{user_permission_id} ] );

                                                                # user permission is not set
                                                                if ( !$permission_created ) {
                                                                    $dbh->rollback;

                                                                    $cb->( status [ 500, q[Error creation user token permissions] ] );

                                                                    return;
                                                                }
                                                            }

                                                            $dbh->commit;

                                                            $cb->(
                                                                status 201,
                                                                {   id    => $user_token->{result}->{id},
                                                                    token => $user_token->{result}->{token},
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
                            }

                            return;
                        }
                    );
                }
            }

            return;
        }
    );

    return;
}

sub remove_user_token ( $self, $user_token_id, $cb ) {
    if ( $self->dbh->do( q[DELETE OR IGNORE FROM api_user_token WHERE id = ?], [$user_token_id] ) ) {
        $cb->( status 200 );
    }
    else {
        $cb->( status [ 404, 'User token not found' ] );
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
## |    3 | 6, 126               | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 6                    | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_auth_user_token' declared but not  |
## |      |                      | used                                                                                                           |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 177, 203, 211, 217   | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::sqlite::UserToken

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
