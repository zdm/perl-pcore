package Pcore::App::API::Backend::Local::sqlite::Register;

use Pcore -role, -promise, -status;

sub _connect_app_instance ( $self, $local, $app_instance_id, $app_instance_version, $app_roles, $app_permissions, $cb ) {
    $self->get_app_instance(
        $app_instance_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $app_instance = $res->{app_instance};

            # update add instance
            if ( !$self->dbh->do( q[UPDATE OR IGNORE api_app_instance SET version = ?, last_connected_ts = ? WHERE id = ?], [ $app_instance_version, time, $app_instance_id ] ) ) {
                $cb->( status [ 500, 'Update app instance error' ] );

                return;
            }

            # add app permissions;
            $self->_add_app_permissions(
                $self->dbh,
                $app_instance->{app_id},
                $app_permissions,
                sub ($status) {

                    # error adding permissions
                    if ( !$status && $status != 304 ) {
                        $cb->($status);

                        return;
                    }

                    if ($local) {
                        $self->_connect_local_app_instance(
                            $app_instance->{app_id},
                            $app_instance_id,
                            sub ($status) {
                                if ( !$status ) {
                                    $cb->($status);

                                    return;
                                }

                                $self->_connect_app_instance1( $app_instance->{app_id}, $app_roles, $cb );

                                return;
                            }
                        );
                    }
                    else {
                        $self->_connect_app_instance1( $app_instance->{app_id}, $app_roles, $cb );
                    }

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub _connect_app_instance1 ( $self, $app_id, $app_roles, $cb ) {

    # check, that all app permissions are enabled
    if ( my $permissions = $self->dbh->selectall( q[SELECT enabled FROM api_app WHERE id = ?], [$app_id] ) ) {
        for ( $permissions->@* ) {
            if ( !$_->{enabled} ) {
                $cb->( status [ 400, 'App permisisons are disabled' ] );

                return;
            }
        }
    }

    # add app roles
    $self->_add_app_roles(
        $app_id,
        $app_roles,
        sub ($status) {
            if ( !$status && $status != 304 ) {
                $cb->($status);

                return;
            }

            # app instance connected
            $cb->( status 200 );

            return;
        }
    );

    return;
}

sub _connect_local_app_instance ( $self, $app_id, $app_instance_id, $cb ) {

    # enabled app
    $self->dbh->do( q[UPDATE api_app SET enabled = 1 WHERE id = ?], [$app_id] );

    # enabled app instance
    $self->dbh->do( q[UPDATE api_app_instance SET enabled = 1 WHERE id = ?], [$app_instance_id] );

    # enabled all app permissions
    $self->dbh->do( q[UPDATE api_app_permissions SET enabled = 1 WHERE app_id = ?], [$app_id] );

    # create root user
    $self->_create_root_user(
        sub ( $res ) {
            if ( !$res && $res != 304 ) {
                $cb->($res);

                return;
            }

            if ( $res->{password} ) {
                say "Root user created: root / $res->{password}";
            }

            $self->{app}->{api}->on_local_app_instance_connect(
                sub ($res) {
                    $cb->($res);

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub _add_app_permissions ( $self, $dbh, $app_id, $permissions, $cb ) {
    my ( $error, $modified );

    my $cv = AE::cv sub {
        if ($error) { $cb->( status [ 400, join q[, ], $error->@* ] ) }
        elsif ( !$modified ) { $cb->( status 304 ) }
        else                 { $cb->( status 201 ) }

        return;
    };

    $cv->begin;

    if ( !$permissions ) {
        $cv->end;

        return;
    }

    for my $permission ( $permissions->@* ) {
        $cv->begin;

        $self->get_app_role(
            $permission,
            sub ( $res ) {
                if ( !$res ) {
                    push $error->@*, $permission;
                }
                else {
                    my $role = $res->{role};

                    # permission is not exists
                    if ( !$dbh->selectrow( q[SELECT FROM api_app_permission WHERE app_id = ? AND role_id = ?], [ $app_id, $role->{id} ] ) ) {

                        # create new disabled app permisison record
                        if ( $dbh->do( q[INSERT OR IGNORE INTO api_app_permissions (app_id, role_id, enabled) VALUES (?, ?, 0)], [ $app_id, $role->{id} ] ) ) {
                            $modified = 1;
                        }
                        else {
                            push $error->@*, $permission;
                        }
                    }
                }

                $cv->end;

                return;
            }
        );
    }

    $cv->end;

    return;
}

sub _add_app_roles ( $self, $app_id, $app_roles, $cb ) {
    my ( $error, $modified );

    my $cv = AE::cv sub {
        if    ($error)       { $cb->( status 500 ) }
        elsif ( !$modified ) { $cb->( status 304 ) }
        else                 { $cb->( status 201 ) }

        return;
    };

    $cv->begin;

    for my $role_name ( keys $app_roles->%* ) {
        if ( $self->dbh->do( q[INSERT OR IGNORE INTO api_app_role (app_id, name, desc, enabled) VALUES (?, ?, ?, 1)], [ $app_id, $role_name, $app_roles->{$role_name} ] ) ) {
            $modified = 1;
        }
    }

    $cv->end;

    return;
}

sub _create_root_user ( $self, $cb ) {
    $self->get_user(
        1,
        sub ( $res ) {

            # user_id 1 already exists
            if ( $res != 404 ) {
                $cb->( status 304 );

                return;
            }

            my $user = $res->{user};

            # generate random root password
            my $root_password = P->data->to_b64_url( P->random->bytes(32) );

            # generate root password hash
            $self->_generate_user_password_hash(
                'root',
                $root_password,
                sub ( $res ) {
                    if ( !$res ) {
                        $cb->($res);

                        return;
                    }

                    if ( $self->dbh->do( q[INSERT OR IGNORE INTO api_user (id, name, hash, enabled, created_ts) VALUES (1, ?, ?, 1, ?)], [ 'root', $res->{hash}, time ] ) ) {
                        $cb->( status 200, password => $root_password );
                    }
                    else {
                        $cb->( status [ 500, 'Error creating root user' ] );
                    }

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
## |    3 | 5, 70, 104, 143, 199 | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 5                    | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_connect_app_instance' declared but |
## |      |                      |  not used                                                                                                      |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::sqlite::Register

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
