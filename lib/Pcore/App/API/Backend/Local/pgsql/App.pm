package Pcore::App::API::Backend::Local::pgsql::App;

use Pcore -role, -result;
use Pcore::Util::UUID qw[uuid_str];

sub get_app ( $self, $app_id, $cb ) {
    $self->_get_app( $self->dbh, $app_id, $cb );

    return;
}

sub _get_app ( $self, $dbh, $app_id, $cb ) {

    # $app_id is id
    if ( $app_id =~ /\A[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}\z/sm ) {
        $dbh->selectrow(
            q[SELECT * FROM api_app WHERE id = ?],
            [$app_id],
            sub ( $dbh, $res, $data ) {
                if ($data) {
                    $cb->( result 200, $data );
                }
                else {

                    # app not found
                    $cb->( result [ 404, 'App not found' ] );
                }

                return;
            }
        );
    }

    # $app_id is name
    else {
        $dbh->selectrow(
            q[SELECT * FROM api_app WHERE name = ?],
            [$app_id],
            sub ( $dbh, $res, $data ) {
                if ($data) {
                    $cb->( result 200, $data );
                }
                else {

                    # app not found
                    $cb->( result [ 404, 'App not found' ] );
                }

                return;
            }
        );
    }

    return;
}

sub create_app ( $self, $name, $desc, $permissions, $cb ) {

    # validate app name
    if ( !$self->{app}->{api}->validate_name($name) ) {
        $cb->( result [ 400, 'App name is not valid' ] );

        return;
    }

    my $dbh = $self->dbh;

    $dbh->begin_work(
        sub ( $dbh, $res ) {

            # create app
            $dbh->do(
                q[INSERT INTO "api_app" ("id", "name", "desc", "created_ts") VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING],
                [ uuid_str, $name, $desc, time ],
                sub ( $dbh, $res, $data ) {
                    my $created = $res ? 1 : 0;

                    $self->_get_app(
                        $dbh, $name,
                        sub ($app) {
                            if ( !$app ) {
                                $dbh->rollback(
                                    sub ( $dbh, $res ) {
                                        $cb->( result [ 400, 'Error creating app' ] );

                                        return;
                                    }
                                );
                            }
                            else {
                                $self->add_app_permissions(
                                    $app->{data}->{id},
                                    $permissions,
                                    sub ($res) {
                                        if ( !$res && $res != 304 ) {
                                            $dbh->rollback(
                                                sub ( $dbh, $res ) {
                                                    $cb->($res);

                                                    return;
                                                }
                                            );
                                        }
                                        else {
                                            $dbh->commit(
                                                sub ( $dbh, $res ) {
                                                    $cb->( result $created ? 201 : 304, $app->{data} );

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

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub check_app_permissions_approved ( $self, $app_id, $cb ) {

    # app is root
    if ( $app_id eq $self->{app}->{id} ) {
        $cb->( result 200 );

        return;
    }

    $self->dbh->selectall(
        q[SELECT * FROM "api_app_permission" WHERE "app_id" = ? AND "approved" = 0],
        [$app_id],
        sub ( $dbh, $res, $data ) {
            if ($data) {
                $cb->( result [ 400, 'App permissions are not approved' ] );
            }
            else {
                $cb->( result 200 );
            }

            return;
        }
    );

    return;
}

sub add_app_permissions ( $self, $app_id, $app_permissions, $cb ) {
    $self->resolve_app_roles(
        $app_permissions,
        sub ($roles) {
            if ( !$roles ) {
                $cb->($roles);
            }
            else {

                # index roles by role_id
                $roles = $roles->{data};

                $self->dbh->do(
                    [ 'INSERT INTO "api_app_permissions" ("id", "app_id", "app_role_id", "approved") VALUES', [ map { [ uuid_str, $app_id, $_, 0 ] } keys $roles->%* ], 'ON CONFLICT DO NOTHING' ],
                    sub ( $dbh, $res, $data ) {

                        # TODO replace $res with modified rows
                        $cb->( result $res ? 200 : 304 );

                        return;
                    }
                );
            }

            return;
        }
    );

    return;
}

# TODO
sub add_app_roles ( $self, $app_id, $app_roles, $cb ) {

    # validate identifiers
    for my $role_name ( keys $app_roles->%* ) {

        # validate app name
        if ( !$self->{app}->{api}->validate_name($role_name) ) {
            $cb->( result [ 400, 'Role name is not valid' ] );

            return;
        }
    }

    $self->get_app(
        $app_id,
        sub ($app) {
            if ( !$app ) {
                $cb->($app);
            }
            else {
                my $modified;

                for my $role_name ( keys $app_roles->%* ) {
                    $modified = 1 if $self->dbh->do( q[INSERT OR IGNORE INTO api_app_role (id, app_id, name, desc) VALUES (?, ?, ?, ?)], [ uuid_str, $app->{data}->{id}, $role_name, $app_roles->{$role_name} ] );
                }

                $cb->( result $modified ? 200 : 304 );

            }

            return;
        }
    );

    return;
}

# APP ROLES
sub get_app_role ( $self, $role_id, $cb ) {

    # $role_id is role id
    if ( $role_id =~ /\A[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}\z/sm ) {
        $self->dbh->selectrow(
            q[SELECT * FROM "api_app_role" WHERE "id" = ?],
            [$role_id],
            sub ( $dbh, $res, $data ) {
                if ($data) {
                    $cb->( result 200, $data );
                }
                else {
                    $cb->( result [ 404, qq[App role "$role_id" not found] ] );
                }

                return;
            }
        );
    }

    # $role id is app_id/role_name
    else {
        my ( $app_id, $role_name ) = split m[/]sm, $role_id;

        # $app_id is app id
        if ( $app_id =~ /\A[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}\z/sm ) {
            $self->dbh->selectrow(
                q[SELECT * FROM "api_app_role" WHERE "app_id" = ? AND "name" = ?],
                [ $app_id, $role_name ],
                sub ( $dbh, $res, $data ) {
                    if ($data) {
                        $cb->( result 200, $data );
                    }
                    else {
                        $cb->( result [ 404, qq[App role "$role_id" not found] ] );
                    }

                    return;
                }
            );
        }

        # $app_id is app name
        else {
            $self->dbh->selectrow(
                q[SELECT "api_app_role".* FROM "api_app", "api_app_role" WHERE "api_app"."name" = ? AND "api_app"."id" = "api_app_role"."app_id" AND "api_app_role"."name" = ?],
                [ $app_id, $role_name ],
                sub ( $dbh, $res, $data ) {
                    if ($data) {
                        $cb->( result 200, $data );
                    }
                    else {
                        $cb->( result [ 404, qq[App role "$role_id" not found] ] );
                    }

                    return;
                }
            );
        }
    }

    return;
}

# return resolved app roles, indexed by role id
sub resolve_app_roles ( $self, $roles, $cb ) {
    my ( $resolved_roles, $errors );

    my $cv = AE::cv sub {
        if ($errors) {
            $cb->( result [ 400, 'Error resolving app roles' ], $errors );
        }
        else {
            $cb->( result 200, $resolved_roles );
        }

        return;
    };

    $cv->begin;

    for my $role_id ( $roles->@* ) {
        $cv->begin;

        $self->get_app_role(
            $role_id,
            sub ($res) {
                if ($res) {
                    $resolved_roles->{ $res->{data}->{id} } = $res->{data};
                }
                else {
                    $errors->{$role_id} = $res->{reason};
                }

                $cv->end;

                return;
            }
        );
    }

    $cv->end;

    return;
}

sub get_app_roles ( $self, $app_id, $cb ) {

    # resolve app id
    $self->get_app(
        $app_id,
        sub ($app) {
            if ( !$app ) {
                $cb->($app);
            }
            else {
                $self->dbh->selectall(
                    q[SELECT * FROM "api_app_role" WHERE "app_id" = ?],
                    [ $app->{data}->{id} ],
                    sub ( $dbh, $res, $data ) {
                        $cb->( 200, $data // [] );

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
## |    3 | 15, 234, 256         | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 161, 193             | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::pgsql::App

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
