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

                $self->_generate_app_instance_token(
                    $app_instance_id,
                    sub ( $token ) {

                        # app instance token generation error
                        if ( !$token ) {
                            $cb->($token);
                        }

                        # app instance token generated
                        else {

                            my $created = $self->dbh->do( q[INSERT OR IGNORE INTO api_app_instance (id, app_id, version, host, created_ts, hash) VALUES (?, ?, ?, ?, ?, ?)], [ $app_instance_id, $app->{result}->{id}, $app_instance_version, $app_instance_host, time, $token->{result}->{hash} ] );

                            if ( !$created ) {
                                $cb->( status [ 400, 'App instance creation error' ] );
                            }
                            else {
                                $self->get_app_instance(
                                    $app_instance_id,
                                    sub ($app_instance) {
                                        if ($app_instance) {
                                            $app_instance->{result}->{token} = $token->{result}->{token};
                                        }

                                        $cb->($app_instance);

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

sub set_app_instance_token ( $self, $app_instance_id, $cb ) {
    $self->_generate_app_instance_token(
        $app_instance_id,
        sub ( $token ) {

            # app instance token generation error
            if ( !$token ) {
                $cb->($token);
            }

            # app instance token generated
            else {

                # set app instance token
                if ( $self->dbh->do( q[UPDATE api_app_instance SET hash = ? WHERE id = ?], [ $token->{result}->{hash}, $app_instance_id ] ) ) {
                    $cb->( status 200, $token->{result}->{token} );
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

sub update_app_instance ( $self, $app_instance_id, $app_instance_version, $cb ) {
    my $updated = $self->dbh->do( q[UPDATE OR IGNORE api_app_instance SET version = ?, last_connected_ts = ? WHERE id = ?], [ $app_instance_version, time, $app_instance_id ] );

    if ( !$updated ) {
        $cb->( status [ 400, 'App instance update error' ] );
    }
    else {
        $cb->( status 200 );
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
## |    3 | 19, 105              | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
