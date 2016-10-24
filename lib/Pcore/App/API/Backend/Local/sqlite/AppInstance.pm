package Pcore::App::API::Backend::Local::sqlite::AppInstance;

use Pcore -role, -promise, -status;

sub get_app_instance ( $self, $app_instance_id, $cb ) {
    if ( my $app_instance = $self->dbh->selectrow( q[SELECT * FROM api_app_instance WHERE id = ?], [$app_instance_id] ) ) {
        delete $app_instance->{hash};

        $cb->( status 200, app_instance => $app_instance );
    }
    else {
        $cb->( status [ 404, 'App instance not found' ] );
    }

    return;
}

sub set_app_instance_token ( $self, $app_instance_id, $cb ) {
    $self->_generate_app_instance_token(
        $app_instance_id,
        sub ( $res ) {

            # app instance token generation error
            if ( !$res ) {
                $cb->($res);
            }

            # app instance token generated
            else {

                # set app instance token
                if ( $self->dbh->do( q[UPDATE api_app_instance SET hash = ? WHERE id = ?], [ $res->{hash}, $app_instance_id ] ) ) {
                    $cb->( status 200, token => $res->{token} );
                }

                # set token error
                else {
                    $cb->( status [ 500, 'Error creation app instance token' ] );
                }
            }

            return;
        }
    );

    return;
}

sub set_app_instance_enabled ( $self, $app_instance_id, $enabled, $cb ) {
    $self->get_app_instance(
        $app_instance_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            if ( ( $enabled && !$res->{app_instance}->{enabled} ) || ( !$enabled && $res->{app_instance}->{enabled} ) ) {
                if ( $self->dbh->do( q[UPDATE api_app_instance SET enabled = ? WHERE id = ?], [ !!$enabled, $app_instance_id ] ) ) {
                    $cb->( status 200 );
                }
                else {
                    $cb->( status [ 500, 'Error set app instance enabled' ] );
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

sub remove_app_instance ( $self, $app_instance_id, $cb ) {
    if ( $self->dbh->do( q[DELETE FROM api_app_instance WHERE id = ?], [$app_instance_id] ) ) {
        $cb->( status 200 );
    }
    else {
        $cb->( status [ 404, 'Error remmoving app instance' ] );
    }

    return;
}

sub get_app_instance_roles ( $self, $app_id, $cb ) {
    if ( my $roles = $self->dbh->selectall( q[SELECT id, name, enabled FROM api_app_role WHERE app_id = ?], [$app_id] ) ) {
        $cb->( status 200, roles => $roles );
    }
    else {
        $cb->( status 200, roles => [] );
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
## |    3 | 49                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::sqlite::AppInstance

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
