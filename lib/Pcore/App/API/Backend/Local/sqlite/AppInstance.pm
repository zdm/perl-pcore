package Pcore::App::API::Backend::Local::sqlite::AppInstance;

use Pcore -role, -promise, -status;
use Pcore::Util::UUID qw[uuid_str];

sub get_app_instance ( $self, $app_instance_id, $cb ) {
    if ( my $app_instance = $self->dbh->selectrow( q[SELECT * FROM api_app_instance WHERE id = ?], [$app_instance_id] ) ) {
        delete $app_instance->{hash};

        $cb->( status 200, $app_instance );
    }
    else {
        $cb->( status [ 404, 'App instance not found' ] );
    }

    return;
}

sub create_app_instance ( $self, $app_id, $app_instance_host, $app_instance_version, $cb ) {
    $self->get_app(
        $app_id,
        sub ($app) {
            if ( !$app ) {
                $cb->($app);
            }
            else {
                my $app_instance_id = uuid_str;

                my $created = $self->dbh->do( q[INSERT OR IGNORE INTO api_app_instance (id, app_id, version, host, created_ts) VALUES (?, ?, ?, ?, ?)], [ $app_instance_id, $app->{result}->{id}, $app_instance_version, $app_instance_host, time ] );

                if ( !$created ) {
                    $cb->( status [ 400, 'App instance creation error' ] );
                }
                else {
                    $self->get_app_instance(
                        $app_instance_id,
                        sub ($app_instance) {
                            $cb->($app_instance);

                            return;
                        }
                    );
                }
            }

            return;
        }
    );

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
                    $cb->( status 200, $res->{token} );
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

# TODO

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
## |    3 | 19                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
