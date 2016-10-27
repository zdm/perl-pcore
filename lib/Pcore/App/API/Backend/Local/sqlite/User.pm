package Pcore::App::API::Backend::Local::sqlite::User;

use Pcore -role, -promise, -status;
use Pcore::Util::UUID qw[uuid_str];

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
                my $root_password = P->random->bytes_hex(16);

                $self->_generate_user_password_hash(
                    'root',
                    $root_password,
                    sub ( $password_hash ) {
                        if ( !$password_hash ) {
                            $cb->($password_hash);

                            return;
                        }

                        my $created = $self->dbh->do( q[INSERT OR IGNORE INTO api_user (id, name, enabled, created_ts, hash) VALUES (?, ?, 1, ?, ?)], [ uuid_str, 'root', time, $password_hash->{result}->{hash} ] );

                        if ( !$created ) {
                            $cb->( status [ 500, 'Error creating root user' ] );
                        }
                        else {
                            $cb->( status 200, { root_password => $root_password } );
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

# TODO generate and set root user password
sub set_root_password ( $self, $cb ) {
    return;
}

sub create_user ( $self, $base_user_id, $user_name, $password, $permissions, $cb ) {
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

                                # generate user password hash
                                $self->_generate_user_password_hash(
                                    $user_name,
                                    $password,
                                    sub ( $password_hash ) {

                                        # password hash generation error
                                        if ( !$password_hash ) {
                                            $cb->($password_hash);
                                        }

                                        # password hash generated
                                        else {
                                            my $dbh = $self->dbh;

                                            $dbh->begin_work;

                                            my $user_id = uuid_str;

                                            my $created = $dbh->do( q[INSERT OR IGNORE INTO api_user (id, name, enabled, created_ts, hash) VALUES (?, ?, 1, ?, ?)], [ $user_id, $user_name, time, $password_hash->{result}->{hash} ] );

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

# TODO only root can update root user
sub set_user_password ( $self, $user_id, $user_password_utf8, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $user = $res->{user};

            $self->_generate_user_password_hash(
                $user->{name},
                $user_password_utf8,
                sub ( $res ) {
                    if ( !$res ) {
                        $cb->($res);

                        return;
                    }

                    if ( !$self->dbh->do( q[UPDATE api_user SET hash = ? WHERE id = ?], [ $res->{result}->{hash}, $user->{id} ] ) ) {
                        $cb->( status [ 500, 'Error setting user password' ] );

                        return;
                    }

                    $cb->( status 200 );

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub set_user_enabled ( $self, $user_id, $enabled, $cb ) {
    $self->get_user(
        $user_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            if ( ( $enabled && !$res->{user}->{enabled} ) || ( !$enabled && $res->{user}->{enabled} ) ) {
                if ( $self->dbh->do( q[UPDATE OR IGNORE api_user SET enabled = ? WHERE id = ?], [ !!$enabled, $res->{user}->{id} ] ) ) {
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
## |    3 | 24                   | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 102                  | Subroutines::ProhibitExcessComplexity - Subroutine "create_user" with high complexity score (21)               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 102, 269             | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 185, 240             | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
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
