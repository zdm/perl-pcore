package Pcore::App::API::Backend::Local::sqlite::UserSession;

use Pcore -role, -promise, -status;

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
## |    3 | 5                    | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
