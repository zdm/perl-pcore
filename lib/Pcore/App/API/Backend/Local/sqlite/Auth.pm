package Pcore::App::API::Backend::Local::sqlite::Auth;

use Pcore -role, -promise, -status;

sub _auth_user_password ( $self, $source_app_instance_id, $user_name_utf8, $private_token, $cb ) {
    state $q1 = <<'SQL';
        SELECT
            api_app_role.name AS source_app_role_name
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

    my $get_permissions = sub {
        my $user_id = $user->{id};

        my $auth = {
            user_id   => $user_id,
            user_name => $user_name_utf8,
            enabled   => $user->{enabled},
        };

        my $tags = {    #
            user_id => $user_id,
        };

        # root user
        if ( $user_name_utf8 eq 'root' ) {
            $auth->{permissions} = {};
        }

        # non-root user
        else {

            # get permissions
            if ( my $roles = $self->dbh->selectall( $q1, [ $source_app_instance_id, $user_id ] ) ) {
                for my $row ( $roles->@* ) {
                    $auth->{permissions}->{ $row->{source_app_role_name} } = 1;
                }
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

sub _auth_app_instance_token ( $self, $source_app_instance_id, $app_instance_id, $private_token, $cb ) {
    state $sql1 = <<'SQL';
        SELECT
            api_app_instance.app_id,
            api_app_instance.hash,
            api_app.enabled AS app_enabled,
            api_app_instance.enabled AS app_instance_enabled
        FROM
            api_app,
            api_app_instance
        WHERE
            api_app_instance.app_id = api_app.id
            AND api_app_instance.id = ?
SQL

    state $sql2 = <<'SQL';
        SELECT
            api_app_role.name AS source_app_role_name
        FROM
            api_app_instance,
            api_app_role,
            api_app_permissions
        WHERE
            api_app_instance.id = ?                              --- source app_instance_id
            AND api_app_role.app_id = api_app_instance.app_id    --- link source_app_instance_role to source_app
            AND api_app_role.enabled = 1                         --- source_app_role must be enabled

            AND api_app_permissions.role_id = api_app_role.id    --- link permission to role
            AND api_app_permissions.enabled = 1                  --- permission must be enabled
            AND api_app_permissions.app_id = ?                   --- link permission to target app id
SQL

    # get app instance
    my $res = $self->dbh->selectrow( $sql1, [$app_instance_id] );

    # app instance not found
    if ( !$res ) {
        $cb->( status [ 404, 'App instance not found' ] );

        return;
    }

    my $continue = sub {
        my $app_id = $res->{app_id};

        my $auth = {
            app_id          => $app_id,
            app_instance_id => $app_instance_id,
            enabled         => $res->{app_enabled} && $res->{app_instance_enabled},
        };

        my $tags = {
            app_id          => $res->{app_id},
            app_instance_id => $app_instance_id,
        };

        # get permissions
        if ( my $roles = $self->dbh->selectall( $sql2, [ $source_app_instance_id, $app_id ] ) ) {
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
            $private_token,
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

# TODO
sub _auth_user_session ( $self, $source_app_instance_id, $user_token_id, $private_token, $cb ) {
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

    # get user token instance
    my $res = $self->dbh->selectrow( $sql1, [$user_token_id] );

    # user token not found
    if ( !$res ) {
        $cb->( status [ 404, 'User token not found' ] );

        return;
    }

    my $continue = sub {
        my $user_id = $res->{user_id};

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
            $private_token,
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 5, 97, 197, 303      | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 |                      | Subroutines::ProhibitUnusedPrivateSubroutines                                                                  |
## |      | 5                    | * Private subroutine/method '_auth_user_password' declared but not used                                        |
## |      | 97                   | * Private subroutine/method '_auth_app_instance_token' declared but not used                                   |
## |      | 197                  | * Private subroutine/method '_auth_user_token' declared but not used                                           |
## |      | 303                  | * Private subroutine/method '_auth_user_session' declared but not used                                         |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::sqlite::Auth

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
