package Pcore::App::API::Backend::Local::sqlite::UserToken;

use Pcore -role, -promise, -status;

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

    # root user
    if ( $user_id =~ /\A(1|root)\z/sm ) {
        $cb->( status [ 400, 'Root user token creation error' ] );

        return;
    }

    # not root user, get user permissions
    $self->get_user_permissions(
        $user_id,
        sub ($res) {

            # get user permissions error
            if ( !$res ) {
                $cb->($res);

                return;
            }

            # creator permissions, indexed by role_id
            my $user_permissions = { map { $_->{role_id} => $_ } $res->{user_permissions}->@* };

            # resolve roles
            my ( $role_error, $roles );

            my $cv = AE::cv sub {

                # roles resolving error
                if ($role_error) {
                    $cb->( status [ 400, 'Invalid permissions: ' . join q[, ], $role_error->@* ] );

                    return;
                }

                # resolve user
                $self->get_user(
                    $user_id,
                    sub ($res) {

                        # get user error
                        if ( !$res ) {
                            $cb->($res);

                            return;
                        }

                        my $user = $res->{user};

                        # generate user token hash
                        $self->_generate_user_token(
                            $user->{id},
                            sub ( $res ) {

                                # token generation error
                                if ( !$res ) {
                                    $cb->( status [ 500, 'User token creation error' ] );

                                    return;
                                }

                                my $user_token_id = $res->{token_id};

                                my $user_token_hash = $res->{hash};

                                my $dbh = $self->dbh;

                                $dbh->begin_work;

                                # insert user token
                                if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_token (id, user_id, desc, created_ts, hash) VALUES (?, ?, ?, ?, ?)], [ $user_token_id, $user->{id}, $desc // q[], time, $user_token_hash ] ) ) {
                                    $dbh->rollback;

                                    $cb->( status [ 500, 'User token creation error' ] );

                                    return;
                                }

                                # create user token permissions
                                for my $role_id ( keys $roles->%* ) {
                                    if ( !$dbh->do( q[INSERT OR IGNORE INTO api_user_token_permissions (user_token_id, user_permissions_id) VALUES (?, ?)], [ $user_token_id, $role_id ] ) ) {
                                        $dbh->rollback;

                                        $cb->( status [ 500, 'User token creation error' ] );

                                        return;
                                    }
                                }

                                $dbh->commit;

                                $cb->( status 201, token => $res->{token} );

                                return;
                            }
                        );

                        return;
                    }
                );

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
                            if ( !exists $user_permissions->{ $res->{role}->{id} } ) {
                                push $role_error->@*, $permission;
                            }
                            else {
                                $roles->{ $res->{role}->{id} } = $res->{role};
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
    );

    return;
}

sub set_user_token_enabled ( $self, $user_token_id, $enabled, $cb ) {
    $self->get_user_token(
        $user_token_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);
            }
            else {
                my $user_token = $res->{user_token};

                if ( ( $enabled && !$user_token->{enabled} ) || ( !$enabled && $user_token->{enabled} ) ) {
                    if ( $self->dbh->do( q[UPDATE OR IGNORE api_user_token SET enabled = ? WHERE id = ?], [ !!$enabled, $user_token->{id} ] ) ) {
                        $cb->( status 200 );
                    }
                    else {
                        $cb->( status [ 500, 'Error set user token enabled' ] );
                    }
                }
                else {

                    # not modified
                    $cb->( status 304 );
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
## |    3 | 20, 162              | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 23                   | RegularExpressions::ProhibitFixedStringMatches - Use 'eq' or hash instead of fixed-pattern regexps             |
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
