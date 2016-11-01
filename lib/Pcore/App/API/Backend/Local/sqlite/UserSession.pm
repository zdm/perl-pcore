package Pcore::App::API::Backend::Local::sqlite::UserSession;

use Pcore -role, -promise, -status;
use Pcore::App::API qw[:CONST];

# TODO tags
sub _auth_user_session ( $self, $source_app_instance_id, $user_session_id, $private_token, $cb ) {
    state $q1 = <<'SQL';
        SELECT
            api_app_role.name AS app_role_name
        FROM
            api_app_instance,
            api_app_role,
            api_user_permission
        WHERE
            api_app_instance.id = ?
            AND api_app_role.app_id = api_app_instance.app_id
            AND api_app_role.id = api_user_permission.app_role_id
            AND api_user_permission.user_id = ?
SQL

    # get user session
    my $user_session = $self->dbh->selectrow(
        <<'SQL',
            SELECT
                api_user.id AS user_id,
                api_user.name AS user_name,
                api_user.enabled AS user_enabled,
                api_user_session.hash AS user_session_hash
            FROM
                api_user,
                api_user_session
            WHERE
                api_user.id = api_user_session.user_id
                AND api_user_session.id = ?
SQL
        [$user_session_id]
    );

    # user session not found
    if ( !$user_session ) {
        $cb->( status [ 404, 'User session not found' ] );

        return;
    }

    # user disabled
    if ( !$user_session->{user_enabled} ) {
        $cb->( status [ 404, 'User disabled' ] );

        return;
    }

    my $get_permissions = sub {
        my $auth = {
            token_type => $TOKEN_TYPE_USER_TOKEN,
            token_id   => $user_session_id,

            is_user   => 1,
            is_root   => $user_session->{user_name} eq 'root',
            user_id   => $user_session->{user_id},
            user_name => $user_session->{user_name},

            is_app          => 0,
            app_id          => undef,
            app_instance_id => undef,
        };

        my $tags = {};

        # get permissions
        if ( my $roles = $self->dbh->selectall( $q1, [ $source_app_instance_id, $user_session->{user_id} ] ) ) {
            $auth->{permissions} = { map { $_->{app_role_name} => 1 } $roles->@* };
        }
        else {
            $auth->{permissions} = {};
        }

        $cb->( status 200, { auth => $auth, tags => $tags } );

        return;
    };

    if ($private_token) {

        # verify token
        $self->_verify_token_hash(
            $private_token,
            $user_session->{user_session_hash},
            $user_session->{user_id},
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

sub create_user_session ( $self, $user_id, $cb ) {

    # get user
    $self->get_user(
        $user_id,
        sub ($user) {

            # get user error
            if ( !$user ) {
                $cb->($user);
            }

            # user is disabled
            elsif ( !$user->{result}->{enabled} ) {
                $cb->( status [ 400, q[User is disabled] ] );
            }

            # user ok
            else {

                # generate session token
                $self->_generate_token(
                    $TOKEN_TYPE_USER_SESSION,
                    $user->{result}->{id},
                    sub ($token) {

                        # token generation error
                        if ( !$token ) {
                            $cb->($token);
                        }

                        # token geneerated
                        else {
                            my $created = $self->dbh->do( q[INSERT OR IGNORE INTO api_user_session (id, user_id, created_ts, hash) VALUES (?, ?, ?, ?)], [ $token->{result}->{id}, $user->{result}->{id}, time, $token->{result}->{hash} ] );

                            if ( !$created ) {
                                $cb->( status [ 500, q[Session creation error] ] );
                            }
                            else {
                                $cb->(
                                    status 201,
                                    {   id    => $token->{result}->{id},
                                        token => $token->{result}->{token},
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 7                    | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 7                    | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_auth_user_session' declared but    |
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
