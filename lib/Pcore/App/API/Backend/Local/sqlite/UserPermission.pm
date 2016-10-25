package Pcore::App::API::Backend::Local::sqlite::UserPermission;

use Pcore -role, -promise, -status;

# TODO root user
sub set_user_permissions ( $self, $creator_user_id, $user_id, $permissions, $cb ) {

    # root user
    if ( $user_id =~ /\A(1|root)\z/sm ) {
        $cb->( status 304 );

        return;
    }

    # not root user, get creator permissions
    $self->get_user_permissions(
        $creator_user_id,
        sub ( $res ) {

            # get permissions error
            if ( !$res ) {
                $cb->($res);

                return;
            }

            # creator permissions, indexed by role_id
            my $creator_permissions = { map { $_->{role_id} => $_ } $res->{user_permissions}->@* };

            # get user permissions
            $self->get_user_permissions(
                $user_id,
                sub ($res) {

                    # get permissions error
                    if ( !$res ) {
                        $cb->($res);

                        return;
                    }

                    # user permissions, indexed by role_id
                    my $user_permissions = { map { $_->{role_id} => $_ } $res->{user_permissions}->@* };

                    my ( $role_error, $roles );

                    my $cv = AE::cv sub {
                        if ($role_error) {
                            $cb->( status [ 400, 'Invalid permissions: ' . join q[, ], $role_error->@* ] );

                            return;
                        }

                        my $add_roles;

                        for my $role_id ( keys $roles->%* ) {

                            # role doesn't exists in the base creator user permissions
                            if ( !exists $creator_permissions->{$role_id} ) {
                                $cb->( status [ 400, qq[Invalid permission: $role_id] ] );

                                return;
                            }

                            # role should be added
                            if ( !exists $user_permissions->{$role_id} ) {
                                push $add_roles->@*, $role_id;
                            }
                        }

                        my $remove_roles;

                        for my $role_id ( keys $user_permissions->%* ) {

                            # role should be removed
                            push $remove_roles->@*, $role_id if !exists $roles->{$role_id};
                        }

                        if ( $add_roles || $remove_roles ) {
                            my $dbh = $self->dbh;

                            $dbh->begin_work;

                            if ($remove_roles) {
                                my $res = eval { $dbh->do( [ q[DELETE FROM api_user_permissions WHERE id IN], $remove_roles ] ) };

                                if ($@) {
                                    $dbh->rollback;

                                    $cb->( status 400 );
                                }
                            }

                            if ($add_roles) {

                                # resolve user id
                                $self->get_user(
                                    $user_id,
                                    sub ($res) {
                                        if ( !$res ) {
                                            $dbh->rollback;

                                            $cb->($res);

                                            return;
                                        }

                                        for my $role_id ( $add_roles->@* ) {
                                            if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_permissions (user_id, role_id, enabled) VALUES (?, ?, 1) ], [ $res->{user}->{id}, $role_id ] ) ) {
                                                $dbh->rollback;

                                                $cb->( status 400 );

                                                return;
                                            }
                                        }

                                        $dbh->commit;

                                        $cb->( status 200 );

                                        return;
                                    }
                                );
                            }
                            else {
                                $dbh->commit;

                                $cb->( status 200 );
                            }
                        }

                        # nothing to do
                        else {

                            # not modified
                            $cb->( status 304 );
                        }

                        return;
                    };

                    $cv->begin;

                    # resolve permissions
                    for my $permission ( $permissions->@* ) {
                        $cv->begin;

                        $self->get_app_role(
                            $permission,
                            sub ($res) {
                                if ( !$res ) {
                                    push $role_error->@*, $permission;
                                }
                                else {
                                    $roles->{ $res->{role}->{id} } = $res->{role};
                                }

                                $cv->end;

                                return;
                            }
                        );
                    }

                    $cv->end;

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub add_user_permissions ( $self, $creator_user_id, $user_id, $permissions, $cb ) {

    # root user
    if ( $user_id =~ /\A(1|root)\z/sm ) {
        $cb->( status 304 );

        return;
    }

    # not root user, get creator permissions
    $self->get_user_permissions(
        $creator_user_id,
        sub ( $res ) {

            # get permissions error
            if ( !$res ) {
                $cb->($res);

                return;
            }

            # creator permissions, indexed by role_id
            my $creator_permissions = { map { $_->{role_id} => $_ } $res->{user_permissions}->@* };

            # get user permissions
            $self->get_user_permissions(
                $user_id,
                sub ($res) {

                    # get permissions error
                    if ( !$res ) {
                        $cb->($res);

                        return;
                    }

                    # user permissions, indexed by role_id
                    my $user_permissions = { map { $_->{role_id} => $_ } $res->{user_permissions}->@* };

                    my ( $role_error, $roles );

                    my $cv = AE::cv sub {
                        if ($role_error) {
                            $cb->( status [ 400, 'Invalid permissions: ' . join q[, ], $role_error->@* ] );

                            return;
                        }

                        my $add_roles;

                        for my $role_id ( keys $roles->%* ) {

                            # role doesn't exists in the base creator user permissions
                            if ( !exists $creator_permissions->{$role_id} ) {
                                $cb->( status [ 400, qq[Invalid permission: $role_id] ] );

                                return;
                            }

                            # role should be added
                            if ( !exists $user_permissions->{$role_id} ) {
                                push $add_roles->@*, $role_id;
                            }
                        }

                        # add roles
                        if ($add_roles) {

                            # resolve user id
                            $self->get_user(
                                $user_id,
                                sub ($res) {
                                    if ( !$res ) {
                                        $cb->($res);

                                        return;
                                    }

                                    my $user_id = $res->{user}->{id};

                                    my $dbh = $self->dbh;

                                    $dbh->begin_work;

                                    for my $role_id ( $add_roles->@* ) {
                                        if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_permissions (user_id, role_id, enabled) VALUES (?, ?, 1) ], [ $user_id, $role_id ] ) ) {
                                            $dbh->rollback;

                                            $cb->( status [ 400, qq[Error creating user permission: $role_id] ] );

                                            return;
                                        }
                                    }

                                    $dbh->commit;

                                    $cb->( status 200 );

                                    return;
                                }
                            );
                        }

                        # nothing to do
                        else {

                            # not modified
                            $cb->( status 304 );
                        }

                        return;
                    };

                    $cv->begin;

                    # resolve permissions
                    for my $permission ( $permissions->@* ) {
                        $cv->begin;

                        $self->get_app_role(
                            $permission,
                            sub ($res) {
                                if ( !$res ) {
                                    push $role_error->@*, $permission;
                                }
                                else {
                                    $roles->{ $res->{role}->{id} } = $res->{role};
                                }

                                $cv->end;

                                return;
                            }
                        );
                    }

                    $cv->end;

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
## |    3 | 6                    | Subroutines::ProhibitExcessComplexity - Subroutine "set_user_permissions" with high complexity score (23)      |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 6, 179               | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 9, 182               | RegularExpressions::ProhibitFixedStringMatches - Use 'eq' or hash instead of fixed-pattern regexps             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::sqlite::UserPermission

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
