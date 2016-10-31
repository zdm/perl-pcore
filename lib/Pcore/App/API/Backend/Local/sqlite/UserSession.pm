package Pcore::App::API::Backend::Local::sqlite::UserSession;

use Pcore -role, -promise, -status;

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

sub create_user_session ( $self, $user_id, $user_agent, $remote_ip, $remote_ip_geo, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $user = $res->{user};

            my $dbh = $self->dbh;

            # create blank user token
            if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_session (user_id, created_ts, user_agent, remote_ip, remote_ip_geo) VALUES (?, ?, ?, ?, ?)], [ $user->{id}, time, $user_agent, $remote_ip, $remote_ip_geo ] ) ) {
                $cb->( status [ 500, 'User session creation error' ] );

                return;
            }

            # get user token id
            my $user_session_id = $dbh->last_insert_id;

            # generate user token hash
            $self->_generate_user_session(
                $user_session_id,
                sub ( $res ) {
                    if ( !$res ) {

                        # rollback
                        $dbh->do( q[DELETE FROM api_user_session WHERE id = ?], [$user_session_id] );

                        $cb->( status [ 500, 'User session creation error' ] );

                        return;
                    }

                    if ( !$dbh->do( q[UPDATE OR IGNORE api_user_session SET hash = ? WHERE id = ?], [ $res->{hash}, $user_session_id ] ) ) {

                        # rollback
                        $dbh->do( q[DELETE FROM api_user_session WHERE id = ?], [$user_session_id] );

                        $cb->( status [ 500, 'User session creation error' ] );

                        return;
                    }

                    $cb->( status 201, session => $res->{session} );

                    return;
                }
            );

            return;
        }
    );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 6, 111               | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 6                    | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_auth_user_session' declared but    |
## |      |                      | not used                                                                                                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::sqlite::UserSession

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
