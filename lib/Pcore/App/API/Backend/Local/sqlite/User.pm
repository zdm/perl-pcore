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

# TODO permissions, enabled
sub create_user ( $self, $user_name, $password, $cb ) {

    # validate user name
    if ( !$self->{app}->{api}->validate_name($user_name) || $user_name eq 'root' ) {
        $cb->( status [ 400, 'User name is not valid' ] );

        return;
    }

    my $dbh = $self->dbh;

    # user created
    if ( $dbh->do( q[INSERT OR IGNORE INTO api_user (name, enabled, created_ts) VALUES (?, ?, ?)], [ $user_name, 0, time ] ) ) {
        my $user_id = $dbh->last_insert_id;

        # set password
        $self->set_user_password(
            $user_id,
            $password,
            sub ($status) {
                if ($status) {

                    # enable user
                    $self->set_user_enabled(
                        $user_id, 1,
                        sub ($status) {
                            if ($status) {
                                $cb->( status 201, user_id => $user_id );
                            }
                            else {
                                # rollback
                                $dbh->do( q[DELETE OR IGNORE FROM api_user WHERE id = ?], [$user_id] );

                                $cb->($status);
                            }

                            return;
                        }
                    );
                }
                else {

                    # rollback
                    $dbh->do( q[DELETE OR IGNORE FROM api_user WHERE id = ?], [$user_id] );

                    $cb->($status);
                }

                return;
            }
        );
    }

    # user already exists
    else {
        my $user_id = $dbh->selectval( 'SELECT id FROM api_user WHERE name = ?', [$user_name] )->$*;

        # name already exists
        $cb->( status [ 409, 'User already exists' ], user_id => $user_id );
    }

    return;
}

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

                    if ( !$self->dbh->do( q[UPDATE api_user SET hash = ? WHERE id = ?], [ $res->{hash}, $user->{id} ] ) ) {
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 24                   | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 162                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
